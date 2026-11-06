import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/core/portal_client.dart';
import 'package:neu_portal/core/webvpn.dart';
import 'package:neu_portal/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'auto chooses direct on campus even with a saved gateway ticket',
    () async {
      final requests = <Uri>[];
      final client = PortalClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            '教务管理系统 jwapp',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.dispose);
      client.cookies.absorbRaw(
        Uri.parse(WebVPN.base),
        'wengine_vpn_ticket=saved; Path=/; Secure',
      );
      client.adoptGatewayTicket();
      await client.prepareAccess();
      expect(client.webvpnOn, isFalse);
      expect(client.hasWebVPNTicket, isTrue);
      expect(requests, hasLength(2));
      expect(
        client.maybeWrap('https://jwxt.neu.edu.cn/jwapp'),
        'https://jwxt.neu.edu.cn/jwapp',
      );
    },
  );

  for (final response in [
    http.Response('', 302, headers: {'location': WebVPN.base}),
    http.Response(
      '',
      302,
      headers: {
        'location':
            'https://pass.neu.edu.cn/tpass/login?service=${Uri.encodeComponent(WebVPN.casService)}',
      },
    ),
    http.Response('Forbidden', 403),
    http.Response('Proxy error', 502),
    http.Response(
      '请登录酒店 Wi-Fi',
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    ),
    http.Response(
      '仅用于我校师生在校外登录',
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    ),
  ]) {
    test(
      'off-campus response ${response.statusCode} ${response.body} uses VPN',
      () async {
        final client = PortalClient(
          httpClient: MockClient((_) async => response),
        );
        addTearDown(client.dispose);
        await client.prepareAccess();
        expect(client.webvpnOn, isTrue);
        expect(
          client.maybeWrap('http://ecard.neu.edu.cn/selflogin/login.aspx'),
          WebVPN.wrap('http://ecard.neu.edu.cn/selflogin/login.aspx'),
        );
      },
    );
  }

  test('campus authentication redirects prove direct reachability', () async {
    final client = PortalClient(
      httpClient: MockClient(
        (request) async => http.Response(
          '',
          302,
          headers: {
            'location': request.url.host == 'jwxt.neu.edu.cn'
                ? 'https://pass.neu.edu.cn/tpass/login?service=jwxt'
                : '/selflogin/login.aspx',
          },
        ),
      ),
    );
    addTearDown(client.dispose);
    await client.prepareAccess();
    expect(client.webvpnOn, isFalse);
  });

  test('network changes reselect both ways and keep gateway cookies', () async {
    var campus = false;
    final client = PortalClient(
      httpClient: MockClient(
        (_) async => http.Response(
          campus ? '教务系统 jwapp' : 'Forbidden',
          campus ? 200 : 403,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );
    addTearDown(client.dispose);
    client.cookies.absorbRaw(
      Uri.parse(WebVPN.base),
      'wengine_vpn_ticket=saved; Path=/; Secure',
    );
    await client.prepareAccess();
    expect(client.webvpnOn, isTrue);
    campus = true;
    client.invalidateAccessRoute();
    await client.prepareAccess();
    expect(client.webvpnOn, isFalse);
    expect(client.hasWebVPNTicket, isTrue);
    campus = false;
    client.invalidateAccessRoute();
    await client.prepareAccess();
    expect(client.webvpnOn, isTrue);
  });

  test(
    'parallel callers share probes and invalidate stale in-flight results',
    () async {
      final gate = Completer<void>();
      var count = 0;
      final client = PortalClient(
        httpClient: MockClient((_) async {
          count++;
          if (count <= 2) {
            await gate.future;
            return http.Response('jwapp', 200);
          }
          return http.Response('', 403);
        }),
      );
      addTearDown(client.dispose);
      final first = client.prepareAccess();
      final second = client.prepareAccess();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      client.invalidateAccessRoute();
      gate.complete();
      await Future.wait([first, second]);
      expect(count, 4);
      expect(client.webvpnOn, isTrue);
    },
  );

  for (final mode in [AccessMode.direct, AccessMode.webvpn]) {
    test(
      'manual $mode skips probes and applies to cached gateway links',
      () async {
        final client = PortalClient(
          httpClient: MockClient(
            (_) async => throw StateError('manual selection must skip probes'),
          ),
        )..accessMode = mode;
        addTearDown(client.dispose);
        await client.prepareAccess();
        const direct = 'http://219.216.96.4:8080/a%20b?ticket=ST%2B1#tab';
        final wrapped = WebVPN.wrap(direct);
        expect(
          client.maybeWrap(wrapped),
          mode == AccessMode.direct ? direct : wrapped,
        );
        expect(
          client.maybeWrap('https://pass.neu.edu.cn/tpass/login'),
          'https://pass.neu.edu.cn/tpass/login',
        );
        expect(
          client.maybeWrap('https://example.com/?next=jwxt.neu.edu.cn'),
          'https://example.com/?next=jwxt.neu.edu.cn',
        );
      },
    );
  }

  test('portal APIs and their redirects use the selected gateway', () async {
    final requests = <Uri>[];
    final client = PortalClient(
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://personal.neu.edu.cn/portal/apps?type=all',
            },
          );
        }
        return http.Response(
          jsonEncode({
            'e': 0,
            'd': {'list': []},
          }),
          200,
        );
      }),
    )..accessMode = AccessMode.webvpn;
    addTearDown(client.dispose);
    await client.fetchApps();
    expect(requests, hasLength(2));
    expect(requests.every((uri) => uri.host == 'webvpn.neu.edu.cn'), isTrue);
    expect(requests.last.query, 'type=all');
  });

  test(
    'a gateway landing without a ticket is not successful authentication',
    () async {
      final client = PortalClient(
        httpClient: MockClient(
          (request) async => request.url.host == 'pass.neu.edu.cn'
              ? http.Response('', 302, headers: {'location': WebVPN.base})
              : http.Response(
                  '仅用于我校师生在校外登录',
                  403,
                  headers: {'content-type': 'text/html; charset=utf-8'},
                ),
        ),
      )..accessMode = AccessMode.webvpn;
      addTearDown(client.dispose);
      expect(await client.ensureWebVPN(), isFalse);
    },
  );

  test(
    'route preference persists and unknown old values default to auto',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.setAccessMode(AccessMode.direct);
      final restored = AppState();
      addTearDown(restored.dispose);
      await restored.loadSettings();
      expect(restored.accessMode, AccessMode.direct);
      SharedPreferences.setMockInitialValues({'network.accessMode': 'old'});
      await restored.loadSettings();
      expect(restored.accessMode, AccessMode.auto);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform exposes automatic and manual routes', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final state = AppState();
      try {
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: const MaterialApp(home: ProfilePage()),
          ),
        );
        await tester.pumpAndSettle();
        final segments = find.byType(AdaptiveSegments<AccessMode>);
        await tester.dragUntilVisible(
          segments,
          find.byType(CustomScrollView),
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: segments, matching: find.text('直连')),
        );
        await tester.pumpAndSettle();
        expect(state.accessMode, AccessMode.direct);
        expect(state.accessStatus, '当前线路为直连');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        state.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
