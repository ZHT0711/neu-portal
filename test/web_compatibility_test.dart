import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/ios_glass.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/web_policy.dart';
import 'package:neu_portal/core/web_cookies.dart';
import 'package:neu_portal/core/webvpn.dart';
import 'package:neu_portal/pages/webview_page.dart';

void main() {
  testWidgets('gateway login visits the portal and waits for populated profile', (
    tester,
  ) async {
    final previous = WebViewPlatform.instance;
    final fake = _FakeWebPlatform();
    WebViewPlatform.instance = fake;
    final state = _CapturingLoginState();
    try {
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WebViewPage(
                        title: '登录',
                        url: WebVPN.base,
                        loginMode: true,
                      ),
                    ),
                  ),
                  child: const Text('网页登录'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('网页登录'));
      await tester.pump();
      // The fake does not finish navigation until the next microtask, so the
      // JavaScript handler is installed before the portal polls its profile.
      var reads = 0;
      fake.controller!.javascript = (script) async {
        if (script == 'navigator.userAgent') return 'Test WebKit';
        if (!fake.controller!.url!.startsWith(WebVPN.wrap(kPortalBase))) {
          return '{}';
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        reads++;
        if (reads == 1) return '{"uid":"42"}';
        if (reads == 2) return '{"uid":"42","name":"测试同学"}';
        // WebKit can return a JSON-quoted JSON string.
        return jsonEncode(
          '{"uid":"42","name":"测试同学","xgh":"20260042","identity":"本科生","depart":"计算机学院","email":"test@example.edu"}',
        );
      };
      for (var i = 0; i < 30 && state.captured == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(fake.controller!.requests.map((u) => u.toString()), [
        WebVPN.base,
        WebVPN.casService,
        WebVPN.wrap(kPortalBase),
      ]);
      expect(state.captured?.hasCoreProfile, isTrue);
      expect(state.captured?.email, 'test@example.edu');
      expect(state.agent, 'Test WebKit');
      expect(find.byType(WebViewPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      if (previous != null) WebViewPlatform.instance = previous;
      state.dispose();
    }
  });

  test(
    'native cookie handoff normalizes Android URL domains and reads proxy paths',
    () async {
      final previous = WebViewPlatform.instance;
      final fake = _FakeWebPlatform();
      WebViewPlatform.instance = fake;
      fake.cookieResponse = (uri) => [
        WebViewCookie(
          name: 'SESS_ID',
          value: 'test-session',
          domain: uri.toString(),
        ),
        const WebViewCookie(
          name: 'CASTGC',
          value: 'test-cas',
          domain: '.neu.edu.cn',
          path: '/tpass',
        ),
      ];
      try {
        final cookies = await captureWebViewCookies(Uri.parse(kPortalBase));
        expect(cookies.first.domain, 'personal.neu.edu.cn');
        expect(cookies.last.domain, '.neu.edu.cn');
        expect(cookies.last.path, '/tpass');
        await captureWebLoginCookies();
        expect(
          fake.cookieQueries,
          contains(Uri.parse(WebVPN.wrap(kPortalBase))),
        );
      } finally {
        if (previous != null) WebViewPlatform.instance = previous;
      }
    },
  );

  test('explicit HTTP entries keep protocol, ports and SSO query parameters', () {
    for (final entry in [
      'http://ecard.neu.edu.cn/selflogin/login.aspx',
      'http://210.30.202.96:8080',
      'http://ipgw.neu.edu.cn:8800/sso/default/neusoft?service=http%3A%2F%2Fexample.com',
    ]) {
      expect(PortalWebPolicy.normalize(' "$entry" '), entry);
    }
    expect(
      PortalWebPolicy.normalize('210.30.202.96:8080'),
      'http://210.30.202.96:8080',
    );
    expect(
      PortalWebPolicy.normalize('ecard.neu.edu.cn:8800/sso'),
      'http://ecard.neu.edu.cn:8800/sso',
    );
    expect(PortalWebPolicy.isWebUrl(Uri.parse('javascript:alert(1)')), isFalse);
    expect(PortalWebPolicy.isWebUrl(Uri.parse('file:///etc/passwd')), isFalse);
  });

  test('HTTP retry uses the current campus URL without downgrading CAS', () {
    expect(
      PortalWebPolicy.httpAlternative(
        Uri.parse('https://ecard.neu.edu.cn:8443/home?tab=2'),
      ),
      Uri.parse('http://ecard.neu.edu.cn:8443/home?tab=2'),
    );
    expect(
      PortalWebPolicy.httpAlternative(
        Uri.parse('https://ecard.neu.edu.cn:443/home'),
      ),
      Uri.parse('http://ecard.neu.edu.cn/home'),
    );
    for (final url in [
      'https://pass.neu.edu.cn/tpass/login',
      'https://personal.neu.edu.cn/portal',
      'https://example.com',
      'https://10.attacker.com',
    ]) {
      expect(PortalWebPolicy.httpAlternative(Uri.parse(url)), isNull);
    }
  });

  test('only the HTTPS CAS origin qualifies for credential injection', () {
    expect(
      PortalWebPolicy.isCasLogin(
        Uri.parse('https://pass.neu.edu.cn/tpass/login?service=x'),
      ),
      isTrue,
    );
    for (final url in [
      'http://pass.neu.edu.cn/tpass/login',
      'https://pass.neu.edu.cn.attacker.com/tpass/login',
      'https://example.com/?next=pass.neu.edu.cn/tpass/login',
      'https://pass.neu.edu.cn:8443/tpass/login',
    ]) {
      expect(PortalWebPolicy.isCasLogin(Uri.parse(url)), isFalse);
    }
    expect(PortalWebPolicy.userAgent(ios: true, desktop: false), isNull);
    expect(
      PortalWebPolicy.userAgent(ios: true, desktop: true),
      isNot(contains('Chrome')),
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform: HTTP, redirects, retry, copy and asynchronous back', (
      tester,
    ) async {
      final fake = _FakeWebPlatform();
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = fake;
      debugDefaultTargetPlatformOverride = platform;
      final state = AppState();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const WebViewPage(
                          title: '体测系统',
                          url: 'http://210.30.202.96:8080',
                        ),
                      ),
                    ),
                    child: const Text('打开系统'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开系统'));
        await tester.pumpAndSettle();
        final controller = fake.controller!;
        expect(
          controller.requests.single.toString(),
          'http://210.30.202.96:8080',
        );
        if (platform == TargetPlatform.iOS) {
          expect(controller.agents.single, isNull);
        }
        controller.redirect('https://ecard.neu.edu.cn:8443/current?tab=2');
        await tester.pumpAndSettle();
        fake.delegate!.resourceError!(
          WebResourceError(
            errorCode: -1022,
            description: 'ATS',
            isForMainFrame: true,
            url: controller.url,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          controller.requests,
          hasLength(2),
          reason: 'Campus HTTPS failures should automatically retry HTTP',
        );
        expect(
          controller.requests.last.toString(),
          'http://ecard.neu.edu.cn:8443/current?tab=2',
        );
        expect(find.text('重试'), findsNothing);
        // An HTTP service redirecting back to the failed HTTPS origin must not loop.
        controller.redirect('https://ecard.neu.edu.cn:8443/current?tab=2');
        await tester.pumpAndSettle();
        fake.delegate!.resourceError!(
          const WebResourceError(
            errorCode: -1022,
            description: 'ATS',
            isForMainFrame: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.requests, hasLength(2));
        expect(find.text('重试'), findsOneWidget);
        await tester.tap(find.text('重试'));
        await tester.pumpAndSettle();
        expect(
          controller.requests.last.toString(),
          'https://ecard.neu.edu.cn:8443/current?tab=2',
        );
        fake.delegate!.resourceError!(
          const WebResourceError(
            errorCode: -1022,
            description: 'ATS',
            isForMainFrame: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.requests, hasLength(4));
        expect(
          controller.requests.last.toString(),
          'http://ecard.neu.edu.cn:8443/current?tab=2',
        );
        // A failed explicit HTTP request should stay on HTTP, without trying HTTPS.
        fake.delegate!.resourceError!(
          const WebResourceError(
            errorCode: -1004,
            description: 'connection failed',
            isForMainFrame: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.requests, hasLength(4));
        await tester.tap(find.text('重试'));
        await tester.pumpAndSettle();
        expect(controller.requests.last.scheme, 'http');
        controller.redirect('http://ecard.neu.edu.cn:8443/final?tab=3');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('浏览选项'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制当前链接'));
        await tester.pumpAndSettle();
        expect(copied, controller.url);
        if (platform == TargetPlatform.iOS) {
          fake.delegate!.resourceError!(
            const WebResourceError(
              errorCode: -999,
              description: 'cancelled',
              isForMainFrame: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('重试'), findsNothing);
        }
        controller.hasHistory = true;
        controller.redirect(controller.url!);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('后退'));
        await tester.pumpAndSettle();
        expect(controller.backCalls, 1);
        expect(
          find.byType(WebViewPage),
          findsOneWidget,
          reason: 'goBack URL changes asynchronously on WebKit',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        if (previous != null) WebViewPlatform.instance = previous;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
        state.dispose();
      }
    });
  }

  testWidgets('glass fallback honors increased contrast', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(highContrast: true),
          child: Scaffold(
            body: IosGlassSurface(child: SizedBox(width: 200, height: 60)),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeWebPlatform extends WebViewPlatform {
  final cookieQueries = <Uri>[];
  List<WebViewCookie> Function(Uri)? cookieResponse;
  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _FakeCookieManager(params, this);
  _FakeController? controller;
  _FakeNavigation? delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _FakeController(params, this);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _FakeNavigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params, this.host) : super.implementation();
  final _FakeWebPlatform host;
  final requests = <Uri>[];
  final agents = <String?>[];
  String? url;
  bool hasHistory = false;
  int backCalls = 0;
  Future<Object> Function(String)? javascript;

  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      javascript == null ? '{}' : await javascript!(script);
  void redirect(String next) {
    url = next;
    host.delegate!.urlChange?.call(UrlChange(url: next));
    host.delegate!.pageFinished?.call(next);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setUserAgent(String? userAgent) async {
    agents.add(userAgent);
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests.add(params.uri);
    url = params.uri.toString();
    host.delegate!.pageStarted?.call(url!);
    host.delegate!.progress?.call(100);
    redirect(url!);
  }

  @override
  Future<String?> currentUrl() async => url;
  @override
  Future<bool> canGoBack() async => hasHistory;
  @override
  Future<String?> getTitle() async => '校内应用';
  @override
  Future<void> goBack() async {
    backCalls++;
  }
}

class _FakeNavigation extends PlatformNavigationDelegate {
  _FakeNavigation(super.params) : super.implementation();
  PageEventCallback? pageStarted;
  PageEventCallback? pageFinished;
  ProgressCallback? progress;
  WebResourceErrorCallback? resourceError;
  UrlChangeCallback? urlChange;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    pageStarted = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    pageFinished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    progress = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    resourceError = callback;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {
    urlChange = callback;
  }
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakeCookieManager extends PlatformWebViewCookieManager {
  _FakeCookieManager(super.params, this.host) : super.implementation();
  final _FakeWebPlatform host;
  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    host.cookieQueries.add(url);
    return host.cookieResponse?.call(url) ?? [];
  }
}

class _CapturingLoginState extends AppState {
  PortalUser? captured;
  String agent = '';

  @override
  Future<bool> completeWebLogin(
    List<({String name, String value, String domain, String path})> cookies, {
    String userAgent = '',
    String userInfoJson = '',
  }) async {
    captured = PortalUser.fromInfoJson(
      jsonDecode(userInfoJson) as Map<String, dynamic>,
    );
    agent = userAgent;
    return true;
  }
}
