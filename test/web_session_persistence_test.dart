import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/portal_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'session.web.v1';
const _channel = MethodChannel('neu.portal/session_cookies');
const _secure = FlutterSecureStorage();
const _profile = PortalUser(uid: '42', name: '测试同学', sid: '20260042',
    identity: '本科生', department: '计算机学院', email: 'student@example.edu', avatarUrl: '');

List<Map<String, dynamic>> _cookies() => [
  {'name': 'wengine_vpn_ticket', 'value': 'ticket==', 'domain': 'webvpn.neu.edu.cn',
   'path': '/', 'secure': true, 'httpOnly': true, 'hostOnly': true, 'expires': null},
  {'name': 'SESS_ID', 'value': 'portal-session', 'domain': 'webvpn.neu.edu.cn',
   'path': '/proxy/portal', 'secure': true, 'httpOnly': true, 'hostOnly': true, 'expires': null},
  {'name': 'SESS_ID', 'value': 'other-session', 'domain': 'webvpn.neu.edu.cn',
   'path': '/proxy/other', 'secure': true, 'httpOnly': true, 'hostOnly': true, 'expires': null},
];

String _snapshot(List<Map<String, dynamic>> cookies) => jsonEncode({
  'version': 1, 'user': _profile.toInfoJson(), 'userAgent': 'WebView original UA', 'cookies': cookies,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  List<Map<String, dynamic>> nativeCookies = [];
  List<dynamic>? restored;
  setUp(() {
    SharedPreferences.setMockInitialValues({'session.mode': 1});
    FlutterSecureStorage.setMockInitialValues({});
    nativeCookies = _cookies();
    restored = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'read') return nativeCookies;
      if (call.method == 'restore') restored = call.arguments as List;
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('web login saves encrypted session; a fresh state restores without password', () async {
    final first = AppState.withClient(_Client());
    expect(await first.completeWebLogin([
      (name: 'wengine_vpn_ticket', value: 'ticket==', domain: 'webvpn.neu.edu.cn', path: '/'),
    ], userAgent: 'WebView original UA', userInfoJson: jsonEncode(_profile.toInfoJson())), isTrue);
    final saved = jsonDecode((await _secure.read(key: _key))!) as Map;
    expect(saved['cookies'], hasLength(3));
    expect(saved['cookies'][0]['expires'], isNull);
    expect(saved['cookies'][0]['httpOnly'], isTrue);
    expect(await first.storedCredentials(), isNull);
    first.dispose();
    // Simulate a killed WebView process: no cookies remain in its memory.
    nativeCookies = [];
    final client = _Client();
    final restarted = AppState.withClient(client);
    addTearDown(restarted.dispose);
    await restarted.loadSettings();
    await restarted.restoreSession();
    expect(restarted.mode, SessionMode.live);
    expect(restarted.usesWebSession, isTrue);
    expect(restarted.user.toInfoJson(), _profile.toInfoJson());
    expect(client.userAgent, 'WebView original UA');
    expect(client.webvpnOn, isTrue);
    expect(restored, hasLength(3));
    expect(client.cookies.headerFor(Uri.parse('https://webvpn.neu.edu.cn/proxy/portal')),
        contains('SESS_ID=portal-session'));
    expect(client.cookies.headerFor(Uri.parse('https://webvpn.neu.edu.cn/proxy/other')),
        contains('SESS_ID=other-session'));
    expect(client.cookies.headerFor(Uri.parse('http://webvpn.neu.edu.cn/')), isNull);
  });

  for (final failure in [Exception('offline'), PortalException('403')]) {
    test('$failure retains verified profile and tickets on restart', () async {
      FlutterSecureStorage.setMockInitialValues({_key: _snapshot(_cookies())});
      final client = _Client()..failure = failure;
      final state = AppState.withClient(client);
      addTearDown(state.dispose);
      await state.loadSettings();
      await state.restoreSession();
      expect(state.mode, SessionMode.live);
      expect(state.user.department, _profile.department);
      expect(client.hasWebVPNTicket, isTrue);
      expect(await _secure.read(key: _key), isNotNull);
      expect(restored, hasLength(3));
    });
  }

  test('confirmed CAS expiry removes snapshot and does not restore native cookies', () async {
    FlutterSecureStorage.setMockInitialValues({_key: _snapshot(_cookies())});
    final state = AppState.withClient(_Client()
      ..failure = PortalException('login required', sessionExpired: true));
    addTearDown(state.dispose);
    await state.loadSettings();
    await state.restoreSession();
    expect(state.mode, SessionMode.demo);
    expect(await _secure.read(key: _key), isNull);
    expect(restored, isNull);
  });

  test('expired authentication cookies are not revived', () async {
    final cookies = _cookies();
    for (final c in cookies) { c['expires'] = 1; }
    FlutterSecureStorage.setMockInitialValues({_key: _snapshot(cookies)});
    final state = AppState.withClient(_Client());
    addTearDown(state.dispose);
    await state.loadSettings();
    await state.restoreSession();
    expect(state.mode, SessionMode.demo);
    expect(await _secure.read(key: _key), isNull);
  });

  test('logout wins over a background cookie capture already in flight', () async {
    FlutterSecureStorage.setMockInitialValues({_key: _snapshot(_cookies())});
    final state = AppState.withClient(_Client());
    addTearDown(state.dispose);
    await state.loadSettings();
    await state.restoreSession();
    final capturing = Completer<void>();
    final release = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'read') { capturing.complete(); await release.future; return _cookies(); }
      return null;
    });
    final saving = state.persistWebSession();
    await capturing.future;
    final logout = state.logout();
    release.complete();
    await Future.wait([saving, logout]);
    expect(await _secure.read(key: _key), isNull);
    expect(state.mode, SessionMode.demo);
    expect(state.usesWebSession, isFalse);
    final restarted = AppState.withClient(_Client());
    addTearDown(restarted.dispose);
    await restarted.loadSettings();
    await restarted.restoreSession();
    expect(restarted.mode, SessionMode.demo);
  });

  test('Android capture enriches flattened cookies but retains precise HTTP expiry', () async {
    nativeCookies = _cookies().map((c) => {...c, 'metadataKnown': false}).toList();
    final client = _Client();
    final state = AppState.withClient(client);
    addTearDown(state.dispose);
    await state.completeWebLogin([
      (name: 'wengine_vpn_ticket', value: 'ticket==', domain: 'webvpn.neu.edu.cn', path: '/'),
    ], userInfoJson: jsonEncode(_profile.toInfoJson()));
    var saved = jsonDecode((await _secure.read(key: _key))!) as Map;
    expect(saved['cookies'][0]['secure'], isTrue);
    expect(saved['cookies'][0]['httpOnly'], isTrue);
    client.cookies.absorbRaw(Uri.parse('https://webvpn.neu.edu.cn/'),
        'wengine_vpn_ticket=ticket==; Secure; HttpOnly; Expires=Wed, 01 Jan 2031 00:00:00 GMT');
    state.absorbWebSession([
      (name: 'wengine_vpn_ticket', value: 'ticket==', domain: 'webvpn.neu.edu.cn', path: '/'),
    ]);
    await state.persistWebSession();
    saved = jsonDecode((await _secure.read(key: _key))!) as Map;
    expect(saved['cookies'][0]['expires'], DateTime.utc(2031).millisecondsSinceEpoch);
  });

  test('CookieJar preserves Expires, host scope, flags and Max-Age precedence', () {
    final jar = CookieJar();
    jar.absorbRaw(Uri.parse('https://pass.neu.edu.cn/tpass/login'),
      'CASTGC=cas==; Path=/tpass; HttpOnly; Secure; Expires=Wed, 01 Jan 2031 00:00:00 GMT');
    jar.absorbRaw(Uri.parse('https://pass.neu.edu.cn/'),
      'live=yes; Max-Age=3600; Expires=Wed, 01 Jan 2020 00:00:00 GMT');
    final fresh = CookieJar()..restoreSessionCookies(jar.sessionCookies());
    expect(fresh.sessionCookies(), hasLength(2));
    expect(fresh.sessionCookies().first['expires'], DateTime.utc(2031).millisecondsSinceEpoch);
    expect(fresh.sessionCookies().first['httpOnly'], isTrue);
    expect(fresh.headerFor(Uri.parse('https://sub.pass.neu.edu.cn/tpass')), isNull);
    expect(fresh.headerFor(Uri.parse('https://pass.neu.edu.cn/tpass')), contains('CASTGC=cas=='));
    expect(fresh.headerFor(Uri.parse('http://pass.neu.edu.cn/tpass')), isNot(contains('CASTGC=')));
  });

  for (final status in [200, 403]) {
    test('non-destructive validation keeps WAF $status separate from real expiry', () async {
      final client = PortalClient(httpClient: MockClient((_) async => http.Response('WAF temporarily unavailable', status)));
      addTearDown(client.dispose);
      client.restoreSessionCookies(_cookies());
      if (status == 200) {
        expect(await client.validateSavedSession(), isNull);
      } else {
        await expectLater(client.validateSavedSession(), throwsA(isA<PortalException>()
            .having((e) => e.sessionExpired, 'expired', false)));
      }
      expect(client.hasWebVPNTicket, isTrue);
    });
  }

  test('real CAS redirect is positively identified', () async {
    final client = PortalClient(httpClient: MockClient((request) async =>
      request.url.host == 'pass.neu.edu.cn'
        ? http.Response('<input type="password">', 200)
        : http.Response('', 302, headers: {'location': 'https://pass.neu.edu.cn/tpass/login'})));
    addTearDown(client.dispose);
    client.restoreSessionCookies(_cookies());
    await expectLater(client.validateSavedSession(), throwsA(isA<PortalException>()
        .having((e) => e.sessionExpired, 'expired', true)));
  });
}

class _Client extends PortalClient {
  @override
  Future<bool> isCampusNet() async => false;
  Object? failure;
  @override
  Future<PortalUser?> validateSavedSession() async {
    if (failure != null) throw failure!;
    return _profile;
  }
  @override
  Future<bool> ensureWebVPN() async => true;
  @override
  Future<PortalUser> fetchUserInfo() async => _profile;
  @override
  Future<List<PortalApp>> fetchApps() async => [];
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
