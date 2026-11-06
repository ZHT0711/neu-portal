import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/grade_report.dart';
import 'package:neu_portal/core/learning.dart';
import 'package:neu_portal/core/learning_reader.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/portal_client.dart';
import 'package:neu_portal/pages/card_page.dart';
import 'package:neu_portal/pages/grades_page.dart';
import 'package:neu_portal/pages/learning_page.dart';

const course = LearningCourse(
  id: 'NEU-1',
  termID: '2',
  title: '示例课程',
  url: 'https://www.icourse163.org/learn/NEU-1?tid=2',
);
const otherCourse = LearningCourse(
  id: 'NEU-2',
  termID: '3',
  title: '另一课程',
  url: 'https://www.icourse163.org/learn/NEU-2?tid=3',
);

LearningAssignment assignment(String id, LearningCourse course) =>
    LearningAssignment(
      id: id,
      courseKey: course.key,
      courseTitle: course.title,
      title: '同名作业',
      kind: '作业',
      url: course.url,
    );

class GradeClient extends PortalClient {
  final response = Completer<GradeReport>();
  final week = Completer<List<CourseOccurrence>>();
  @override
  Future<List<CourseOccurrence>> fetchWeek(DateTime day) => week.future;
  int calls = 0;
  @override
  Future<GradeReport> fetchGradeReport() {
    calls++;
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a prior account cannot populate the timetable after switching accounts',
    () async {
      final client = GradeClient();
      final state = AppState.withClient(client)..mode = SessionMode.live;
      final response = state.fetchWeek(DateTime(2026, 11, 6));
      final check = expectLater(response, throwsA(isA<PortalException>()));
      state.enterDemo();
      client.week.complete([]);
      await check;
      state.dispose();
    },
  );

  test(
    '307 platform redirects preserve POST encoding, referer and updated cookies',
    () async {
      final client = PortalClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/start') {
            return http.Response(
              '',
              307,
              headers: {
                'location': '/next',
                'set-cookie': 'session=new; Path=/; Secure',
              },
            );
          }
          expect(request.method, 'POST');
          expect(request.body, '{"termId":2}');
          expect(request.headers['content-type'], contains('application/json'));
          expect(
            request.headers['referer'],
            'https://www.icourse163.org/learn/NEU-1',
          );
          expect(request.headers['cookie'], contains('session=new'));
          return http.Response('done', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      final document = await client.readDocument(
        'https://www.icourse163.org/start',
        method: 'POST',
        contentType: 'application/json;charset=UTF-8',
        body: '{"termId":2}',
        referer: 'https://www.icourse163.org/learn/NEU-1',
      );
      expect(document.text, 'done');
      expect(document.url.path, '/next');
    },
  );

  test(
    'partial reports clear successful empty courses, retain failures, deduplicate within course',
    () {
      final previous = LearningReport(
        accountKey: 'one',
        courses: [course, otherCourse],
        assignments: [
          assignment('shared-id', course),
          assignment('shared-id', otherCourse),
        ],
        refreshedCourseKeys: {course.key, otherCourse.key},
      );
      final next = LearningReport(
        accountKey: 'one',
        courses: [course],
        assignments: [],
        refreshedCourseKeys: {course.key},
      ).merging(previous);
      expect(next.assignments.single.courseKey, otherCourse.key);
      expect(next.courses.length, 2);
      final changedAccount = const LearningReport(
        accountKey: 'two',
        courses: [course],
        assignments: [],
        refreshedCourseKeys: {},
      ).merging(previous);
      expect(changedAccount.assignments, isEmpty);
      expect(changedAccount.courses.length, 1);
      final repeated = LearningReport(
        accountKey: 'one',
        courses: [course, otherCourse],
        assignments: [
          assignment('same', course),
          assignment('same', course),
          assignment('same', otherCourse),
        ],
        refreshedCourseKeys: {course.key, otherCourse.key},
      ).merging(previous);
      expect(repeated.assignments.length, 2);
    },
  );

  test(
    'external account fingerprints are domain scoped and never anonymous',
    () {
      final cookies = [
        <String, dynamic>{
          'name': 'NTESSTUDYSI',
          'value': 'secret',
          'domain': '.icourse163.org',
        },
      ];
      final key = learningAccountKey(LearningPlatform.mooc, cookies);
      expect(key.length, 64);
      expect(key, isNot(contains('secret')));
      expect(
        learningAccountKey(LearningPlatform.mooc, [...cookies, ...cookies]),
        key,
      );
      expect(
        () => learningAccountKey(LearningPlatform.mooc, [
          {'name': 'NTESSTUDYSI', 'value': 'secret', 'domain': 'evil.example'},
        ]),
        throwsA(isA<PortalException>()),
      );
      expect(
        () => learningAccountKey(LearningPlatform.chaoxing, []),
        throwsA(isA<PortalException>()),
      );
    },
  );

  test('dates use Beijing end of day, Unix seconds and milliseconds', () {
    final expected = DateTime.utc(2026, 11, 10, 15, 59, 59);
    expect(learningDate('2026/11/10', endOfDay: true), expected);
    expect(learningDate('2026-11-10 23:59:59'), expected);
    expect(learningDate(expected.millisecondsSinceEpoch), expected);
    expect(learningDate(expected.millisecondsSinceEpoch ~/ 1000), expected);
    expect(learningDate('2026/9/8 9:30'), DateTime.utc(2026, 9, 8, 1, 30));
    expect(learningDate('2026年9月8日 9:30'), DateTime.utc(2026, 9, 8, 1, 30));
    expect(learningDate('unknown'), isNull);
    expect(learningDateText(expected), '2026-11-10 23:59');
  });

  test(
    'Chaoxing progress counts unique leaves and rejects incomplete counts',
    () {
      Map<String, dynamic> payload(List<Map<String, dynamic>> nodes) => {
        'data': [
          {
            'course': {
              'data': [
                {
                  'id': '1',
                  'knowledge': {'data': nodes},
                },
              ],
            },
          },
        ],
      };
      final leaf = {
        'id': '2',
        'parentnodeid': '1',
        'finishcount': '3',
        'unfinishcount': '2',
      };
      final progress = LearningProgress.chaoxing(
        payload([
          {'id': '1', 'finishcount': 30, 'jobcount': 50},
          leaf,
          leaf,
          {
            'id': '3',
            'parentnodeid': '1',
            'jobFinishedCount': 1,
            'jobcount': 5,
          },
        ]),
        '1',
      );
      expect(progress.completed, 4);
      expect(progress.total, 10);
      expect(
        () => LearningProgress.chaoxing(
          payload([
            {'id': 2},
          ]),
          '1',
        ),
        throwsA(isA<PortalException>()),
      );
      expect(LearningProgress.chaoxing(payload([]), '1').total, 0);
    },
  );

  test(
    'CG requires all expected problems and all expected tests to be correct',
    () {
      final partial = CGProblem({
        'id': 'p',
        'title': '题目',
        'statusText': '共有测试数据：2 测试数据1 完全正确',
      });
      expect(partial.status, CGStatus.submitted);
      expect(
        CGProblem({'id': 'p', 'statusText': '未提交'}).status,
        CGStatus.notSubmitted,
      );
      expect(
        CGProblem({'id': 'p', 'statusText': '部分正确'}).status,
        CGStatus.needsWork,
      );
      final row = {
        'id': '1',
        'title': '作业',
        'loaded': true,
        'expectedCount': 2,
        'problems': [
          {'id': 'p', 'statusText': '完全正确'},
        ],
      };
      expect(CGAssignment(row).isComplete, isFalse);
      row['expectedCount'] = 1;
      expect(CGAssignment(row).isComplete, isTrue);
      row['loaded'] = false;
      expect(CGAssignment(row).isComplete, isFalse);
    },
  );

  test(
    'MOOC reads 51 regular courses and one SPOC through normal reader entry',
    () async {
      final discoveredPages = <String>[];
      final client = PortalClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.contains('learnerCourse')) {
            final body = jsonDecode(request.body) as Map;
            final type = body['courseType'], page = body['p'] as int;
            discoveredPages.add('$type.$page');
            final ids = type == 2
                ? [52]
                : page == 1
                ? List.generate(50, (i) => i + 1)
                : [51];
            return http.Response(
              jsonEncode({
                'result': {
                  'result': [
                    for (final id in ids)
                      {
                        'id': id,
                        'name': '课程 $id',
                        'mode': type == 2 ? 20 : 0,
                        'schoolPanel': {'shortName': 'NEU'},
                        'termPanel': {'id': id + 100},
                      },
                  ],
                  'pagination': {'totleCount': type == 2 ? 1 : 51},
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (path.endsWith('.rpc')) {
            return http.Response('{"chapters":[]}', 200);
          }
          return http.Response('<html>course</html>', 200);
        }),
      );
      addTearDown(client.dispose);
      client.cookies.absorbRaw(
        Uri.parse('https://www.icourse163.org/'),
        'NTESSTUDYSI=test; Domain=icourse163.org; Path=/; Secure',
      );
      final reader = LearningReader(
        client: client,
        isCurrent: () => true,
        parse: (script, args) async => args.containsKey('course')
            ? {'recognized': true, 'assignments': []}
            : {'courses': []},
      );
      final report = await reader.read(LearningPlatform.mooc);
      expect(discoveredPages, ['1.1', '1.2', '2.1']);
      expect(report.courses.length, 52);
      expect(report.refreshedCourseKeys.length, 52);
      expect(report.courses.last.url, contains('/spoc/learn/'));
    },
  );

  test(
    'grade report retains failed terms and accepts numeric success and empty semesters',
    () {
      final report = GradeReport.fromBrowser({
        'semesters': [
          {
            'code': 'new',
            'response': {
              'code': 0,
              'datas': [
                {'courseName': '数学', 'score': 0, 'credit': 3},
              ],
            },
          },
          {
            'code': 'empty',
            'response': {
              'success': true,
              'data': {'rows': []},
            },
          },
          {
            'code': 'old',
            'response': {'code': '-1'},
          },
        ],
      }).merging([const GradeSemester('旧学期', termCode: 'old', courses: [])]);
      expect(report.semesters.length, 3);
      expect(report.failedTerms, ['old']);
      expect(report.semesters.first.courses.single.score, 0);
    },
  );

  test('native grades continue after a term fails', () async {
    final client = PortalClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('schoolCalendars.do')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'datas': [
                {'itemCode': 'one'},
                {'itemCode': 'bad'},
                {'itemCode': 'two'},
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('scores.do')) {
          return http.Response(
            request.url.queryParameters['termCode'] == 'bad'
                ? '<html>login</html>'
                : '{"code":"0","datas":[]}',
            200,
          );
        }
        return http.Response('home', 200);
      }),
    )..accessMode = AccessMode.direct;
    addTearDown(client.dispose);
    final report = await client.fetchGradeReport();
    expect(report.semesters.map((s) => s.termCode), ['one', 'two']);
    expect(report.failedTerms, ['bad']);
  });

  test(
    'logout generation prevents an old grade response from overwriting demo',
    () async {
      final client = GradeClient();
      final state = AppState.withClient(client)..mode = SessionMode.live;
      final pending = state.loadGrades(force: true);
      state.enterDemo();
      client.response.complete(
        const GradeReport([GradeSemester('stale', courses: [])]),
      );
      await pending;
      expect(state.semesters.any((s) => s.name == 'stale'), isFalse);
      expect(state.gradesLoading, isFalse);
      state.dispose();
    },
  );

  test('browser grades supersede an older in-flight native response', () async {
    final client = GradeClient();
    final state = AppState.withClient(client)..mode = SessionMode.live;
    final pending = state.loadGrades(force: true);
    state.acceptGradeReport(
      const GradeReport([GradeSemester('browser', termCode: '1', courses: [])]),
    );
    client.response.complete(
      const GradeReport([
        GradeSemester('old native', termCode: '1', courses: []),
      ]),
    );
    await pending;
    expect(state.semesters.single.name, 'browser');
    state.dispose();
  });

  test('failed grade refresh keeps previous data and permits retry', () async {
    final client = GradeClient();
    final state = AppState.withClient(client)
      ..mode = SessionMode.live
      ..semesters = [const GradeSemester('retained', courses: [])];
    final pending = state.loadGrades(force: true);
    client.response.completeError(PortalException('offline'));
    await pending;
    expect(state.semesters.single.name, 'retained');
    expect(state.gradesError, 'offline');
    expect(state.gradesLoading, isFalse);
    state.dispose();
  });

  test(
    'card failed refresh preserves valid zero and account reset clears data',
    () {
      final state = AppState();
      state.acceptCardReport({
        'balance': {'balance': 0},
        'month': '2026-11',
        'bills': [],
        'warnings': [],
      });
      expect(
        () => state.acceptCardReport({
          'balance': null,
          'month': '2026-11',
          'bills': null,
          'warnings': ['HTTP 403'],
        }),
        throwsA(isA<PortalException>()),
      );
      expect(state.cardBalance!.balance, 0);
      expect(state.cardMonths['2026-11']!.bills, isEmpty);
      state.acceptLearningReport(
        LearningPlatform.mooc,
        const LearningReport(
          accountKey: 'one',
          courses: [course],
          assignments: [],
          refreshedCourseKeys: {},
        ),
      );
      state.enterDemo();
      expect(state.cardBalance, isNull);
      expect(state.cardMonths, isEmpty);
      expect(state.learningReports, isEmpty);
      state.dispose();
    },
  );

  for (final width in [320.0, 900.0]) {
    for (final page in [
      const LearningPage(),
      const CardPage(),
      const GradesPage(),
    ]) {
      testWidgets('${page.runtimeType} renders empty state at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final state = AppState()
          ..mode = SessionMode.live
          ..semesters = [];
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(home: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      });
    }
  }
}
