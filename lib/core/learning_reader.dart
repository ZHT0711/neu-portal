import 'dart:convert';

import 'package:flutter/services.dart';

import 'learning.dart';
import 'portal_client.dart';

typedef BrowserParser =
    Future<Map<String, dynamic>> Function(
      String script,
      Map<String, Object?> arguments,
    );

class LearningSyncCancelled implements Exception {}

/// Native HTTP handles platform subdomains. Parsing runs in the logged-in browser.
class LearningReader {
  LearningReader({
    required this.client,
    required this.parse,
    required this.isCurrent,
    this.onProgress,
  });
  final PortalClient client;
  final BrowserParser parse;
  final bool Function() isCurrent;
  final void Function(String)? onProgress;

  void check() {
    if (!isCurrent()) throw LearningSyncCancelled();
  }

  Future<({String text, Uri url})> get(String url) async {
    check();
    final result = await client.readDocument(url);
    check();
    return result;
  }

  Future<LearningReport> read(
    LearningPlatform platform, {
    LearningReport? previous,
  }) async {
    final key = learningAccountKey(platform, client.sessionCookies());
    return platform == LearningPlatform.mooc
        ? _mooc(key, previous?.accountKey == key ? previous : null)
        : _chaoxing(key);
  }

  Future<LearningReport> _mooc(
    String accountKey,
    LearningReport? previous,
  ) async {
    final csrf = client.sessionCookies().firstWhere(
      (c) =>
          c['name'] == 'NTESSTUDYSI' &&
          LearningPlatform.mooc.accepts('https://${c['domain']}/'),
    )['value'];
    final courses = <String, LearningCourse>{};
    final warnings = <String>[];
    for (final type in [1, 2]) {
      try {
        for (var page = 1; page <= 20; page++) {
          check();
          final response = await client.readDocument(
            'https://www.icourse163.org/web/j/learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=${Uri.encodeComponent('$csrf')}',
            method: 'POST',
            contentType: 'application/json;charset=UTF-8',
            referer: 'https://www.icourse163.org/home.htm',
            body: jsonEncode({
              'type': 30,
              'p': page,
              'psize': 50,
              'courseType': type,
            }),
          );
          final decoded = decodeMOOCCoursePage(response.text, page, type);
          for (final course in decoded.courses) {
            courses[course.key] = course;
          }
          if (!decoded.hasMore) break;
          if (page == 20) throw PortalException('课程超过 20 页，列表尚未取全');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } catch (e) {
        check();
        warnings.add('${type == 1 ? '普通课程' : '学校 SPOC'}列表未取全 · $e');
      }
    }
    final discovery = await rootBundle.loadString(
      'assets/bridges/mooc_discover.js',
    );
    final found = await parse(discovery, {});
    for (final row in (found['courses'] as List? ?? []).whereType<Map>()) {
      final course = LearningCourse.fromJson(row);
      if (LearningPlatform.mooc.accepts(course.url)) {
        courses[course.key] = course;
      }
    }
    if (warnings.isNotEmpty && previous != null) {
      for (final c in previous.courses) {
        courses.putIfAbsent(c.key, () => c);
      }
    }
    if (courses.isEmpty) {
      throw PortalException(
        warnings.isEmpty ? '未读取到已选课程，请打开慕课课程列表后重试' : warnings.join('\n'),
      );
    }
    final parser = await rootBundle.loadString('assets/bridges/mooc_parser.js');
    final script =
        parser + await rootBundle.loadString('assets/bridges/mooc_course.js');
    final assignments = <LearningAssignment>[];
    final refreshed = <String>{};
    var index = 0;
    for (final course in courses.values) {
      check();
      onProgress?.call('${++index}/${courses.length} · ${course.title}');
      try {
        final page = await get(course.url);
        if (!LearningPlatform.mooc.accepts(page.url.toString())) {
          throw PortalException('请重新登录慕课');
        }
        var html = page.text;
        if (!page.url.path.contains('/spoc/') &&
            RegExp(r'/learn/[^/]+/').hasMatch(page.url.path) &&
            !page.url.path.endsWith('/assessments')) {
          try {
            html += (await get(
              page.url
                  .replace(
                    path: page.url.path.replaceFirstMapped(
                      RegExp(r'(/learn/[^/]+)/.*'),
                      (m) => '${m[1]}/assessments',
                    ),
                    fragment: '',
                  )
                  .toString(),
            )).text;
          } catch (e) {
            check();
            warnings.add('${course.title}的作业与测验列表未读取');
          }
        }
        final responses = await _terms(course.termID, '$csrf', course.url);
        final arguments = <String, Object?>{
          'course': {...course.toJson(), 'url': page.url.toString()},
          'html': html,
          'responses': responses,
        };
        var parsed = await parse(script, arguments);
        final active = course.activeTermID ?? parsed['activeTermID'];
        if (active is String && active.isNotEmpty && active != course.termID) {
          responses.addAll(await _terms(active, '$csrf', course.url));
          parsed = await parse(script, arguments);
        }
        if (parsed['recognized'] != true) {
          throw PortalException('未读取到课程大纲，请打开课程后重试');
        }
        assignments.addAll(_assignments(parsed, LearningPlatform.mooc));
        refreshed.add(course.key);
      } catch (e) {
        check();
        warnings.add('${course.title} · $e');
      }
    }
    if (refreshed.isEmpty) throw PortalException(warnings.join('\n'));
    return LearningReport(
      accountKey: accountKey,
      courses: courses.values.toList(),
      assignments: assignments,
      refreshedCourseKeys: refreshed,
      warnings: warnings,
    );
  }

  Future<List<Map<String, String>>> _terms(
    String term,
    String csrf,
    String referer,
  ) async {
    final responses = <Map<String, String>>[];
    for (final last in [true, false]) {
      check();
      try {
        final response = await client.readDocument(
          'https://www.icourse163.org/web/j/courseBean.${last ? 'getLastLearnedMocTermDto' : 'getMocTermDto'}.rpc?csrfKey=${Uri.encodeComponent(csrf)}',
          method: 'POST',
          referer: referer,
          contentType: last
              ? 'application/json;charset=UTF-8'
              : 'application/x-www-form-urlencoded;charset=UTF-8',
          body: last
              ? jsonEncode({'termId': int.parse(term)})
              : 'termId=${Uri.encodeComponent(term)}&gatewayType=3',
        );
        if (response.text.contains('chapters')) {
          responses.add({'raw': response.text, 'termID': term});
        }
      } catch (_) {
        check();
      }
    }
    return responses;
  }

  static ({List<LearningCourse> courses, bool hasMore}) decodeMOOCCoursePage(
    String text,
    int page,
    int type,
  ) {
    final payload = jsonDecode(text);
    final result = payload is Map ? payload['result'] : null;
    if (result is! Map) throw PortalException('慕课登录已失效，请重新登录');
    final pagination = result['pagination'] is Map
        ? result['pagination'] as Map
        : {};
    final total = int.tryParse(
      '${pagination['total'] ?? pagination['totleCount'] ?? pagination['totalCount']}',
    );
    final rows = result['result'];
    if (rows == null && (page > 1 || (total ?? 0) > 0)) {
      return (courses: [], hasMore: false);
    }
    if (rows is! List) throw PortalException('慕课课程列表格式异常');
    final courses = rows.whereType<Map>().map((row) {
      final school = row['schoolPanel'] is Map ? row['schoolPanel'] as Map : {};
      final term = row['termPanel'] is Map ? row['termPanel'] as Map : {};
      final id = '${row['id']}',
          tid = '${term['id']}',
          abbreviation = '${school['shortName']}';
      if (!RegExp(r'^[1-9]\d*$').hasMatch(id) ||
          !RegExp(r'^[1-9]\d*$').hasMatch(tid) ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(abbreviation) ||
          abbreviation == 'null') {
        throw PortalException('部分课程缺少学校或学期信息');
      }
      final key = '$abbreviation-$id';
      final mode = int.tryParse('${row['mode']}') ?? (type == 2 ? 20 : 0);
      return LearningCourse(
        id: key,
        termID: tid,
        title: '${row['name'] ?? key}',
        url:
            'https://www.icourse163.org/${mode == 0 ? '' : 'spoc/'}learn/$key?tid=$tid',
      );
    }).toList();
    return (
      courses: courses,
      hasMore: rows.length >= 50 && (total == null || page * 50 < total),
    );
  }

  Future<LearningReport> _chaoxing(String key) async {
    final response = await get(
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1',
    );
    final payload = jsonDecode(response.text);
    if (payload is! Map || payload['channelList'] is! List) {
      throw PortalException('请在学习通网页完成登录后同步');
    }
    final courses = <LearningCourse>[];
    final assignments = <LearningAssignment>[];
    final refreshed = <String>{};
    final warnings = <String>[];
    final script = await rootBundle.loadString(
      'assets/bridges/chaoxing_page.js',
    );
    for (final channel in (payload['channelList'] as List).whereType<Map>()) {
      final content = channel['content'];
      if (content is! Map || content['course'] is! Map) continue;
      final clazz = '${content['id']}', cpi = '${content['cpi']}';
      if (!RegExp(r'^\d+$').hasMatch(clazz) ||
          !RegExp(r'^\d+$').hasMatch(cpi)) {
        continue;
      }
      for (final item
          in (content['course']['data'] as List? ?? []).whereType<Map>()) {
        final id = '${item['id']}';
        if (!RegExp(r'^\d+$').hasMatch(id)) continue;
        check();
        final entry = Uri.https(
          'mooc1.chaoxing.com',
          '/visit/stucoursemiddle',
          {
            'courseid': id,
            'clazzid': clazz,
            'cpi': cpi,
            'ismooc2': '1',
            'v': '2',
          },
        ).toString();
        final title = '${item['name'] ?? '课程 $id'}';
        onProgress?.call('${courses.length + 1} · $title');
        LearningProgress? progress;
        String? progressWarning;
        try {
          final result = await get(
            Uri.https('mooc1-api.chaoxing.com', '/gas/clazz', {
              'id': clazz,
              'personid': cpi,
              'view': 'json',
              'fields':
                  'id,course.fields(id,knowledge.fields(id,parentnodeid,layer,finishcount,unfinishcount,jobcount).type(video))',
            }).toString(),
          );
          progress = LearningProgress.chaoxing(jsonDecode(result.text), id);
        } catch (e) {
          check();
          progressWarning = '课程进度未读取 · $e';
        }
        final course = LearningCourse(
          id: id,
          termID: clazz,
          title: title,
          url: entry,
          progress: progress,
          progressWarning: progressWarning,
          deadline: learningDate(content['endDate'], endOfDay: true),
        );
        courses.add(course);
        try {
          final landing = await get(entry);
          final enc = await parse(
            'const doc = new DOMParser().parseFromString(html, "text/html"); return {enc: doc.querySelector("#workEnc, input[name=workEnc]")?.value || ""};',
            {'html': landing.text},
          );
          if ('${enc['enc'] ?? ''}'.isEmpty) {
            throw PortalException('课程作业入口未就绪，请在网页打开课程后重试');
          }
          var lastPage = 1;
          final rows = <LearningAssignment>[];
          for (var page = 1; page <= lastPage; page++) {
            final list = await get(
              Uri.https('mooc1.chaoxing.com', '/mooc-ans/mooc2/work/list', {
                'courseId': id,
                'classId': clazz,
                'cpi': cpi,
                'enc': '${enc['enc']}',
                'pageNum': '$page',
              }).toString(),
            );
            final parsed = await parse(script, {
              'html': list.text,
              'pageURL': list.url.toString(),
              'courseKey': course.key,
              'courseTitle': title,
            });
            if (parsed['recognized'] != true) {
              throw PortalException('作业列表未读取，请在网页完成认证后重试');
            }
            rows.addAll(_assignments(parsed, LearningPlatform.chaoxing));
            final pages = (parsed['pages'] as num?)?.toInt() ?? 1;
            if (pages > lastPage) lastPage = pages;
            if (lastPage > 100) throw PortalException('作业超过 100 页，请在网页查看');
            if (page < lastPage) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          }
          assignments.addAll(rows);
          refreshed.add(course.key);
        } catch (e) {
          check();
          warnings.add('$title · $e');
        }
      }
    }
    if (courses.isEmpty) throw PortalException('学习通未返回课程，请确认已选课账号');
    return LearningReport(
      accountKey: key,
      courses: courses,
      assignments: assignments,
      refreshedCourseKeys: refreshed,
      warnings: warnings,
    );
  }

  List<LearningAssignment> _assignments(
    Map parsed,
    LearningPlatform platform,
  ) => (parsed['assignments'] as List? ?? [])
      .whereType<Map>()
      .map((row) => LearningAssignment.fromJson(row, platform))
      .toList();
}
