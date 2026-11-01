import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/demo_data.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/portal_client.dart';
import 'package:neu_portal/core/webvpn.dart';
import 'package:neu_portal/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = PortalUser(
  uid: '42',
  name: '测试同学',
  sid: '20260042',
  identity: '本科生',
  department: '计算机学院',
  email: 'test@example.edu',
  avatarUrl: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform: missing profile fields remain readable without crashing',
      (tester) async {
        final state = AppState()
          ..mode = SessionMode.live
          ..user = PortalUser.fromInfoJson({});
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(
            AppScope(
              state: state,
              child: const MaterialApp(home: ProfilePage()),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('东大师生'), findsOneWidget);
          expect(find.text('个人资料待同步'), findsOneWidget);
          expect(find.text('重试同步个人资料'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = null;
          state.dispose();
        }
      },
    );
  }

  test(
    'first portal response supplies profile without another request or ticket reset',
    () async {
      final requests = <http.Request>[];
      final client = PortalClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '<script>window.userInfoDSL = ${jsonEncode(profile.toInfoJson())};</script>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.dispose);
      client.absorbWebCookies([
        (
          name: 'wengine_vpn_ticket',
          value: 'test-ticket',
          domain: 'webvpn.neu.edu.cn',
          path: '/',
        ),
      ]);
      final user = await client.fetchUserInfo();
      expect(user.department, profile.department);
      expect(requests.single.url.toString(), WebVPN.wrap(kPortalBase));
      expect(client.hasWebVPNTicket, isTrue);
    },
  );

  test(
    'DSL config without a user is rejected; partial profiles retain populated fields',
    () {
      expect(
        PortalClient.extractUserFromHtml('window.userInfoDSL = {"uid":"42"};'),
        isNull,
      );
      final partial = PortalUser.fromInfoJson({'uid': '42', 'name': ' 测试同学 '});
      expect(partial.hasCoreProfile, isFalse);
      final merged = partial.merge(profile);
      expect(merged.hasCoreProfile, isTrue);
      expect(
        merged.merge(PortalUser.fromInfoJson({'uid': '42', 'name': ''})).email,
        profile.email,
      );
      final other = merged.merge(
        PortalUser.fromInfoJson({'uid': '43', 'xgh': '20260043'}),
      );
      expect(
        other.department,
        isEmpty,
        reason: 'Another account must not inherit personal data',
      );
    },
  );

  test(
    'short public catalog updates entries without removing VPN or cached additions',
    () {
      final merged = mergePortalApps([
        demoApps,
        [
          const PortalApp(
            name: '新服务',
            appId: '900',
            url: 'https://new.neu.edu.cn',
          ),
        ],
        [
          const PortalApp(
            name: '教务系统（新）',
            appId: '138',
            url: 'https://jwxt.neu.edu.cn/new',
          ),
        ],
      ]);
      expect(merged.where((a) => a.appId == '138'), hasLength(1));
      expect(merged.first.url, 'https://jwxt.neu.edu.cn/new');
      expect(merged.take(16).any((a) => a.appId == '2'), isTrue);
      expect(merged.last.appId, '900');
      expect(merged.first.iconUrl, isNotEmpty);
    },
  );

  test(
    'web login fills partial profile and preserves catalog through refresh and restart',
    () async {
      final client = _SessionClient();
      final state = AppState.withClient(client);
      addTearDown(state.dispose);
      state.apps = [
        ...demoApps,
        const PortalApp(
          name: '缓存服务',
          appId: '901',
          url: 'https://cache.neu.edu.cn',
        ),
      ];
      expect(
        await state.completeWebLogin(
          [],
          userInfoJson: '{"uid":"42","name":"测试同学"}',
        ),
        isTrue,
      );
      expect(state.user.department, profile.department);
      expect(state.user.email, profile.email);
      expect(state.apps.any((a) => a.appId == '2'), isTrue);
      expect(state.apps.any((a) => a.appId == '901'), isTrue);

      client.appsResponse = [];
      await state.refresh();
      expect(state.apps.any((a) => a.appId == '2'), isTrue);
      expect(state.apps.any((a) => a.appId == '901'), isTrue);

      final restarted = AppState();
      addTearDown(restarted.dispose);
      await restarted.loadSettings();
      expect(restarted.apps.any((a) => a.appId == '2'), isTrue);
      expect(restarted.apps.any((a) => a.appId == '901'), isTrue);
    },
  );

  test(
    'existing shrunken cache is repaired from the bundled service catalog',
    () async {
      SharedPreferences.setMockInitialValues({
        'cache.apps': jsonEncode([
          {'name': '教务系统（新）', 'appId': '138', 'url': 'https://jwxt.neu.edu.cn'},
        ]),
      });
      final state = AppState();
      addTearDown(state.dispose);
      await state.loadSettings();
      expect(state.apps.length, demoApps.length);
      expect(state.apps.take(16).any((a) => a.name == 'VPN服务'), isTrue);
    },
  );
}

class _SessionClient extends PortalClient {
  List<PortalApp> appsResponse = [
    const PortalApp(
      name: '教务系统（新）',
      appId: '138',
      url: 'https://jwxt.neu.edu.cn',
    ),
  ];
  @override
  bool get isLoggedIn => true;
  @override
  Future<bool> ensureWebVPN() async => true;
  @override
  Future<PortalUser> fetchUserInfo() async => profile;
  @override
  Future<List<PortalApp>> fetchApps() async => appsResponse;
  @override
  Future<List<CourseOccurrence>> fetchWeek(DateTime anyDayInWeek) async => [];
  @override
  Future<List<NewsItem>> fetchNews({int pageSize = 12}) async => [];
  @override
  Future<List<TodoItem>> fetchTodos() async => [];
  @override
  Future<List<DataCard>> fetchDataCards() async => [];
  @override
  Future<List<GradeSemester>> fetchJwxtGrades() async => [];
  @override
  Future<List<String>> fetchHotSearch({int pageSize = 8}) async => [];
}
