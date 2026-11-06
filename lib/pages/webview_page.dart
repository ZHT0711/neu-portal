/// Embedded business browser: preserve HTTP entries and the actual WebKit identity.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../core/app_state.dart';
import '../core/cas_crypto.dart';
import '../core/ios_glass.dart';
import '../core/models.dart';
import '../core/portal_client.dart';
import '../core/portal_document.dart';
import '../core/platform_style.dart';
import '../core/theme.dart';
import '../core/web_policy.dart';
import '../core/web_cookies.dart';
import '../core/webvpn.dart';
import '../core/browser_bridge.dart';
import '../core/learning.dart';
import '../core/learning_reader.dart';
import '../core/grade_report.dart';
import 'login_page.dart';
import 'shell.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.loginMode = false,
  });
  final String title;
  final String url;

  /// 网页登录模式：落地门户/网关后自动吸收会话 Cookie 并完成登录。
  final bool loginMode;
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  late final BrowserBridge _bridge;
  AppState? _state;
  int _accountGeneration = 0;
  int _documentGeneration = 0;
  bool _syncing = false;
  String _syncProgress = '';
  PortalClient? _learningClient;

  String? get _dataTarget {
    if (widget.loginMode) return null;
    final direct = WebVPN.unwrap(_currentUri.toString());
    for (final platform in LearningPlatform.values) {
      if (platform.accepts(direct)) return platform.name;
    }
    final host = Uri.tryParse(direct)?.host;
    if (host == 'jwxt.neu.edu.cn') return 'grades';
    if (host == 'ecard.neu.edu.cn') return 'card';
    return null;
  }

  void _cancelSync() {
    _documentGeneration++;
    _bridge.cancel();
    _learningClient?.dispose();
    _learningClient = null;
    _syncing = false;
  }

  void _accountChanged() {
    if (_state?.dataGeneration == _accountGeneration) return;
    _accountGeneration = _state!.dataGeneration;
    _cancelSync();
    unawaited(_controller.runJavaScript('window.stop();'));
    if (mounted) setState(() {});
  }
  late Uri _currentUri;
  final _progressNotifier = ValueNotifier<double>(0.0);
  bool _viewReady = false;
  Animation<double>? _routeAnimation;
  String? _error;
  String _pageTitle = '';
  bool _needLogin = false;
  int _casAttempts = 0;
  bool _desktop = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  final _httpRetriedOrigins = <String>{};
  bool _webLoginCapturing = false;
  bool _webLoginDone = false;
  bool _gatewayAuthTried = false;
  bool _portalLandingTried = false;
  String _capturedUserInfoJson = '';
  bool _documentHasLoginForm = false;

  bool get _onPersonalPortal =>
      (_currentUri.host == 'personal.neu.edu.cn' &&
          _currentUri.path.startsWith('/portal')) ||
      (_currentUri.host == 'webvpn.neu.edu.cn' &&
          _currentUri.path.startsWith(Uri.parse(WebVPN.wrap(kPortalBase)).path));

  bool get _hasCoreProfile {
    try {
      return PortalUser.fromInfoJson(
          Map<String, dynamic>.from(jsonDecode(_capturedUserInfoJson) as Map))
          .hasCoreProfile;
    } catch (_) {
      return false;
    }
  }

  /// 网页登录模式的导航诊断日志（发给开发者定位校外链路用）。
  final List<String> _diagLog = [];

  void _diag(String event) {
    if (!widget.loginMode) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _diagLog.add('$ts $event');
    debugPrint('[web-login] $ts $event');
  }

  @override
  void initState() {
    super.initState();
    _currentUri = Uri.parse(PortalWebPolicy.normalize(widget.url));
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            javaScriptCanOpenWindowsAutomatically: true,
          )
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);
    _bridge = BrowserBridge(_controller);
    _configureAndLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_state != state) {
      _state?.removeListener(_accountChanged);
      _state = state;
      _accountGeneration = state.dataGeneration;
      state.addListener(_accountChanged);
    }
    final route = ModalRoute.of(context);
    final anim = route?.animation;
    if (anim != null) {
      if (anim.isCompleted) {
        _viewReady = true;
      } else {
        _routeAnimation = anim;
        anim.addStatusListener(_onRouteAnimationStatus);
      }
    } else {
      _viewReady = true;
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = null;
      if (mounted && !_viewReady) {
        setState(() => _viewReady = true);
      }
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_accountChanged);
    _cancelSync();
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _configureAndLoad() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _bridge.install();
      final dark = mounted && Theme.of(context).brightness == Brightness.dark;
      await _controller.setBackgroundColor(
        dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
      );
      await _controller.setUserAgent(
        (!widget.loginMode && mounted ? AppScope.of(context).webUserAgent : null) ??
            PortalWebPolicy.userAgent(ios: isApple, desktop: _desktop),
      );
      final platform = _controller.platform;
      if (platform is WebKitWebViewController) {
        await platform.setAllowsBackForwardNavigationGestures(true);
      }
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onUrlChange: (change) => _rememberUrl(change.url),
          onPageStarted: (url) {
            _cancelSync();
            _rememberUrl(url);
            _diag('跳转 $url');
            _progressNotifier.value = 0.05;
            if (_error != null) mountedSet(() => _error = null);
          },
          onProgress: (value) => _progressNotifier.value = value / 100.0,
          onPageFinished: (_) {
            _progressNotifier.value = 1.0;
            _onPageSettled();
            if (widget.loginMode && !_webLoginDone) {
              _tryCaptureUserInfo();
            }
          },
          onWebResourceError: (error) {
            _diag('资源错误 ${error.errorCode} ${error.url ?? ''} mainFrame=${error.isForMainFrame}');
            // WebKit emits cancellation while redirecting / opening a new target.
            if (!mounted ||
                error.isForMainFrame != true ||
                (isApple && error.errorCode == -999)) {
              return;
            }
            _rememberUrl(error.url);
            final alternative = PortalWebPolicy.httpAlternative(_currentUri);
            // One retry per HTTPS origin in a load cycle, including after SSO redirects.
            if (alternative != null &&
                _httpRetriedOrigins.add(_currentUri.origin)) {
              unawaited(_load(alternative, resetHttpRetry: false));
              return;
            }
            mountedSet(
              () => _error =
                  '加载失败（${error.errorCode}）。请检查校园网或 VPN，'
                  '也可尝试桌面版或系统浏览器。',
            );
          },
        ),
      );
      if (mounted) await _injectCookiesThenLoad();
    } catch (_) {
      mountedSet(() => _error = '暂时无法打开页面，请重试或使用系统浏览器。');
    }
  }

  void _rememberUrl(String? url) {
    final uri = Uri.tryParse(url ?? '');
    if (PortalWebPolicy.isWebUrl(uri)) mountedSet(() => _currentUri = uri!);
  }

  Future<NavigationDecision> _onNavigation(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (request.isMainFrame && mounted && PortalWebPolicy.isWebUrl(uri)) {
      final routed = AppScope.of(context).browserURL(request.url);
      if (routed != request.url) {
        await _load(Uri.parse(routed), resetHttpRetry: false);
        return NavigationDecision.prevent;
      }
    }
    if (PortalWebPolicy.isWebUrl(uri) || request.url == 'about:blank') {
      return NavigationDecision.navigate;
    }
    if (uri != null && PortalWebPolicy.isExternalApp(uri)) {
      await _openExternal(uri);
    }
    return NavigationDecision.prevent;
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Display an actionable error instead of leaking a plugin exception. */
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开，请确认已安装对应应用')));
    }
  }

  Future<void> _onPageSettled() async {
    if (!mounted) return;
    try {
      _rememberUrl(await _controller.currentUrl());
      final back = await _controller.canGoBack();
      bool forward = false;
      try {
        forward = await _controller.canGoForward();
      } catch (_) {}
      final title = await _controller.getTitle();
      mountedSet(() {
        _canGoBack = back;
        _canGoForward = forward;
        if (title != null && title.trim().isNotEmpty) _pageTitle = title;
      });
    } catch (_) {
      /* A page can disappear while the user navigates back. */
    }
    if (!mounted) return;
    // 单点登出自愈：live 模式下页面内 CAS 重登成功（或门户会话刷新）后，
    // 把新会话同步回 App 并刷新数据（e码通退出会连带注销整个 CAS 会话）。
    final state = AppScope.of(context);
    if (!widget.loginMode &&
        state.mode == SessionMode.live &&
        _onPersonalPortal) {
      try {
        await _tryCaptureUserInfo();
        if (_capturedUserInfoJson.isNotEmpty && !_documentHasLoginForm) {
          state.updateWebProfile(PortalUser.fromInfoJson(
              Map<String, dynamic>.from(jsonDecode(_capturedUserInfoJson) as Map)));
        }
        final cookies = await captureWebLoginCookies();
        state.absorbWebSession(cookies
            .map((c) => (name: c.name, value: c.value, domain: c.domain, path: c.path))
            .toList());
        unawaited(state.refresh());
      } catch (_) {}
    }
    // 网页登录模式：落到门户域（直连成功）或网关域（被学校重定向进网关，
    // 但 CAS 已成功、CASTGC 已到手）都收会话并完成登录，不停在页面上。
    if (widget.loginMode && !_webLoginDone) {
      final host = _currentUri.host.toLowerCase();
      // 校外会被学校依次重定向：personal → 网关 → 一网通旧门户（portal），
      // 任何一个业务域落地都视为登录已在页面内完成，回收会话交回 App。
      final landedBusiness = host == 'personal.neu.edu.cn' ||
          host == 'portal.neu.edu.cn' ||
          host == 'webvpn.neu.edu.cn';
      if (landedBusiness) {
        await _tryCaptureUserInfo();
        if (_documentHasLoginForm || _currentUri.path.contains('/tpass/login')) return;
        // 第一次落到网关：先在页面内完成网关自己的 CAS 登录（CASTGC 就在
        // WebView 里），建立网关会话后再回门户，避免停在网关 403 拦截页。
        if (host == 'webvpn.neu.edu.cn' && !_onPersonalPortal && !_gatewayAuthTried) {
          _gatewayAuthTried = true;
          _diag('网关：尝试页面内网关 CAS 登录');
          await _load(Uri.parse(WebVPN.casService));
          return;
        }
        // 网关首页/旧门户没有一号通 DSL，也未必建立了门户 SESS_ID。
        // 网关认证完成后必须在同一 WebView 中进入新门户，再交接会话。
        if (!_onPersonalPortal && !_portalLandingTried) {
          _portalLandingTried = true;
          final target = _gatewayAuthTried || host == 'webvpn.neu.edu.cn'
              ? WebVPN.wrap(kPortalBase) : kPortalBase;
          _diag('进入一号通门户以同步个人资料与服务');
          await _load(Uri.parse(target));
          return;
        }
        _diag('落地 $host，开始回收会话');
        await _completeWebLogin();
        return;
      }
    }
    if (PortalWebPolicy.isCasLogin(_currentUri)) {
      if (!mounted) return;
      final creds = await state.storedCredentials();
      final ok = await _autoCasLogin();
      // 只有确实用已存凭据尝试过自动登录且失败时才是「会话失效」；
      // 全新登录页（未存凭据/网页登录模式）不显示过期横幅。
      if (!ok && creds != null && !widget.loginMode) {
        mountedSet(() => _needLogin = true);
      } else {
        mountedSet(() => _needLogin = false);
      }
    } else {
      mountedSet(() => _needLogin = false);
    }
  }

  /// 在门户页面内读取 window.userInfoDSL（轮询调用，SPA 可能在停稳后才写入）。
  Future<void> _tryCaptureUserInfo() async {
    if (!mounted) return;
    try {
      final v = _unwrapJsResult(await _controller.runJavaScriptReturningResult(
        portalDocumentScript,
      ));
      if (v.isNotEmpty && v != '{}') {
        final document = Map<String, dynamic>.from(jsonDecode(v) as Map);
        _documentHasLoginForm = document['loginForm'] == true;
        if (_documentHasLoginForm) return;
        var next = PortalUser.fromInfoJson(Map<String, dynamic>.from(
            (document['user'] is Map ? document['user'] : document) as Map));
        if (!next.hasCoreProfile && document['sources'] is List) {
          for (final source in document['sources'] as List) {
            final found = PortalClient.extractUserFromHtml('$source');
            if (found != null) next = next.merge(found);
          }
        }
        if (!next.hasProfile) return;
        final previous = _capturedUserInfoJson.isEmpty ? null :
            PortalUser.fromInfoJson(Map<String, dynamic>.from(
                jsonDecode(_capturedUserInfoJson) as Map));
        _capturedUserInfoJson = jsonEncode((previous?.merge(next) ?? next).toInfoJson());
        _diag('userInfoDSL 已捕获');
      }
    } catch (_) {}
  }

  /// 解包 runJavaScriptReturningResult 的返回（WebKit 可能再包一层 JSON 引号）。
  String _unwrapJsResult(Object? value) {
    if (value is! String) return value?.toString() ?? '';
    try {
      final decoded = jsonDecode(value);
      if (decoded is String) return decoded;
    } on FormatException {
      /* WebKit already returns a decoded string. */
    }
    return value;
  }

  /// 读取 WebView 会话 Cookie（iOS: WKHTTPCookieStore；Android: CookieManager）。
  Future<List<WebViewCookie>> _captureCookies(Uri uri) async {
    return captureWebViewCookies(uri);
  }

  /// 吸收会话并完成登录，成功后退出本页回到主界面。
  Future<void> _completeWebLogin() async {
    if (_webLoginCapturing) return;
    _webLoginCapturing = true;
    final state = AppScope.of(context);
    try {
      // 必须等待 JS 调用完成；非空的初始对象不代表资料已填充完整。
      for (var i = 0; i < 6 && mounted; i++) {
        await _tryCaptureUserInfo();
        if (_hasCoreProfile) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
      if (!mounted) return;
      if (_documentHasLoginForm || _currentUri.path.contains('/tpass/login')) {
        _webLoginCapturing = false;
        return;
      }
      final cookies = <WebViewCookie>[
        ...await _captureCookies(Uri.parse('https://pass.neu.edu.cn/tpass/login')),
        ...await _captureCookies(Uri.parse('https://personal.neu.edu.cn/portal')),
        ...await _captureCookies(Uri.parse('https://webvpn.neu.edu.cn/')),
        if (_currentUri.host == 'webvpn.neu.edu.cn')
          ...await _captureCookies(_currentUri),
        ...await _captureCookies(Uri.parse('https://portal.neu.edu.cn/tp_up/')),
      ];
      _diag('回收 ${cookies.length} 枚 Cookie：${cookies.map((c) => '${c.domain}#${c.name}').take(14).join(', ')}');
      _diag('userInfoDSL: ${_capturedUserInfoJson.isEmpty ? '未捕获' : '已捕获'}');
      String ua = '';
      try {
        ua = _unwrapJsResult(await _controller.runJavaScriptReturningResult('navigator.userAgent'));
      } catch (_) {}
      _diag('UA: $ua');
      final ok = await state.completeWebLogin(
        cookies
            .map((c) => (name: c.name, value: c.value, domain: c.domain, path: c.path))
            .toList(),
        userAgent: ua,
        userInfoJson: _capturedUserInfoJson,
      );
      if (!mounted) return;
      if (ok) {
        _diag('登录完成，返回主界面');
        _webLoginDone = true;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacement(
              MaterialPageRoute(builder: (_) => const AdaptiveShell()));
        }
        return;
      }
      _diag('登录未完成：${state.lastError}');
      _webLoginCapturing = false;
      mountedSet(() => _error = state.lastError ?? '网页登录未完成，请重试。');
    } catch (e) {
      _diag('会话回收异常：$e');
      _webLoginCapturing = false;
      if (mounted) mountedSet(() => _error = '网页登录会话回收失败，请重试。');
    }
  }

  Future<bool> _autoCasLogin() async {
    if (_casAttempts >= 2) return false;
    final s = AppScope.of(context);
    final creds = await s.storedCredentials();
    if (creds == null) return false;
    _casAttempts++;
    try {
      String str(Object? value) {
        if (value is! String) return value?.toString() ?? '';
        try {
          final decoded = jsonDecode(value);
          if (decoded is String) return decoded;
        } on FormatException {
          /* WebKit already returns a decoded string. */
        }
        return value;
      }

      final lt = str(
        await _controller.runJavaScriptReturningResult(
          "document.getElementById('lt')?.value || ''",
        ),
      );
      final execution = str(
        await _controller.runJavaScriptReturningResult(
          "document.getElementsByName('execution')[0]?.value || ''",
        ),
      );
      if (lt.isEmpty || execution.isEmpty) return false;
      final rsa = CasCrypto.encrypt(creds.$1 + creds.$2);
      await _controller.runJavaScript("""
        (function(){
          if (location.protocol !== 'https:' || location.hostname !== 'pass.neu.edu.cn' ||
              (location.port && location.port !== '443') ||
              !['/tpass/login', '/tpass/login/'].includes(location.pathname)) return;
          var uIn = document.getElementById('un'); if (uIn) uIn.disabled = true;
          var pIn = document.getElementById('pd'); if (pIn) pIn.disabled = true;
          var f = document.getElementById('rsa'); if (f) f.value = '$rsa';
          var u = document.getElementById('ul'); if (u) u.value = '${creds.$1.length}';
          var p = document.getElementById('pl'); if (p) p.value = '${creds.$2.length}';
          var l = document.getElementById('lt'); if (l) l.value = ${jsonEncode(lt)};
          var e = document.getElementsByName('execution')[0]; if (e) e.value = ${jsonEncode(execution)};
          var ev = document.getElementsByName('_eventId')[0]; if (ev) ev.value = 'submit';
          var form = document.getElementById('loginForm'); if (form) form.submit();
        })();
      """);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _injectCookiesThenLoad() async {
    try {
      final state = AppScope.of(context);
      if (!widget.loginMode || _currentUri.toString() == kNeuCasLoginUrl) {
        await state.prepareBrowserAccess(force: true);
        if (!mounted) return;
        if (widget.loginMode) {
          final portal = state.browserURL(kPortalBase);
          _currentUri = Uri.parse(kNeuCasLoginUrl).replace(
            queryParameters: {
              'service': WebVPN.isWrapped(portal) ? WebVPN.casService : portal,
            },
          );
        }
      }
      // 网页登录与业务页共用原生 Cookie 存储，不把已有 HttpOnly/路径 Cookie
      // 降为普通的根路径 Cookie 再覆盖回去。
      if (state.mode == SessionMode.live && !state.usesWebSession) {
        final manager = WebViewCookieManager();
        for (final cookie in state.browserCookies()) {
          await manager.setCookie(WebViewCookie(name: cookie.name,
              value: cookie.value, domain: cookie.domain, path: cookie.path));
        }
      }
      if (!widget.loginMode) _currentUri = Uri.parse(state.browserURL(_currentUri.toString()));
    } catch (_) {
      /* Sites may still present their own sign-in screen. */
    }
    if (mounted) await _load(_currentUri);
  }

  void mountedSet(VoidCallback change) {
    if (mounted) setState(change);
  }

  Future<void> _load(Uri uri, {bool resetHttpRetry = true}) async {
    if (!PortalWebPolicy.isWebUrl(uri)) return;
    if (resetHttpRetry) _httpRetriedOrigins.clear();
    _progressNotifier.value = 0.05;
    mountedSet(() {
      _currentUri = uri;
      _error = null;
      _casAttempts = 0;
    });
    try {
      await _controller.loadRequest(uri);
    } catch (_) {
      mountedSet(() => _error = '无法加载该地址，请检查网络后重试。');
    }
  }

  Future<void> smartBack() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return; // WebKit updates currentUrl asynchronously after goBack.
      }
    } catch (_) {
      /* No live web history remains. */
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _goForward() async {
    try {
      if (await _controller.canGoForward()) {
        await _controller.goForward();
      }
    } catch (_) {
      /* No live web history remains. */
    }
  }

  Future<void> _goToLogin() async {
    final state = AppScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LoginPage(),
      ),
    );
    if (mounted && state.mode == SessionMode.live) {
      mountedSet(() {
        _needLogin = false;
        _casAttempts = 0;
      });
      await _injectCookiesThenLoad();
    }
  }

  Future<void> _toggleDesktop() async {
    HapticFeedback.selectionClick();
    mountedSet(() => _desktop = !_desktop);
    try {
      await _controller.setUserAgent(
        PortalWebPolicy.userAgent(ios: isApple, desktop: _desktop),
      );
      await _load(_currentUri);
    } catch (_) {
      mountedSet(() => _error = '切换显示模式失败，请重试。');
    }
  }

  Future<List<Map<String, dynamic>>> _platformCookies(
    LearningPlatform platform,
  ) async {
    final urls = platform == LearningPlatform.mooc
        ? ['https://www.icourse163.org/', 'https://icourse163.org/']
        : [
            'https://i.chaoxing.com/',
            'https://chaoxing.com/',
            'https://mooc1-api.chaoxing.com/',
            'https://mooc1.chaoxing.com/',
            'https://passport2.chaoxing.com/',
          ];
    final records = <String, Map<String, dynamic>>{};
    for (final url in urls) {
      for (final cookie in await captureWebViewCookies(Uri.parse(url))) {
        if (cookie.value.isEmpty) continue;
        final row = <String, dynamic>{
          'name': cookie.name,
          'value': cookie.value,
          'domain': cookie.domain.replaceFirst(RegExp(r'^\.'), ''),
          'path': cookie.path,
          'secure': true,
          'httpOnly': true,
          'hostOnly': !cookie.domain.startsWith('.'),
          'metadataKnown': false,
        };
        records['${row['domain']}|${row['path']}|${row['name']}'] = row;
      }
    }
    return records.values.toList();
  }

  Future<void> _syncData() async {
    final target = _dataTarget;
    final state = _state;
    if (_syncing || target == null || state == null) return;
    final document = _documentGeneration;
    final generation = state.dataGeneration;
    bool current() =>
        mounted &&
        document == _documentGeneration &&
        generation == state.dataGeneration &&
        target == _dataTarget;
    setState(() {
      _syncing = true;
      _syncProgress = '正在读取';
    });
    PortalClient? client;
    try {
      if (target == 'mooc' || target == 'chaoxing') {
        final platform = LearningPlatform.values.byName(target);
        final cookies = await _platformCookies(platform);
        if (!current()) return;
        final accountKey = learningAccountKey(platform, cookies);
        client = PortalClient()..restoreSessionCookies(cookies);
        _learningClient = client;
        client.setUserAgent(
          await _controller.getUserAgent() ?? state.webUserAgent ?? '',
        );
        final reader = LearningReader(
          client: client,
          parse: (script, arguments) async {
            if (!current()) throw LearningSyncCancelled();
            final parsed = await _bridge.run(script, arguments);
            if (!current()) throw LearningSyncCancelled();
            return parsed;
          },
          isCurrent: current,
          onProgress: (text) {
            if (current()) setState(() => _syncProgress = text);
          },
        );
        final report = await reader.read(
          platform,
          previous: state.learningReports[platform],
        );
        if (!current()) return;
        final finalKey = learningAccountKey(
          platform,
          await _platformCookies(platform),
        );
        if (!current()) return;
        if (accountKey != finalKey) throw PortalException('平台账号已变化，请重新同步');
        final cookieManager = WebViewCookieManager();
        for (final c in client.browserCookies()) {
          if (!current()) return;
          await cookieManager.setCookie(
            WebViewCookie(
              name: c.name,
              value: c.value,
              domain: c.domain,
              path: c.path,
            ),
          );
        }
        if (current()) state.acceptLearningReport(platform, report);
      } else {
        final script = await rootBundle.loadString(
          'assets/bridges/${target == 'grades'
              ? 'grades'
              : target == 'cg'
              ? 'cg'
              : 'card'}.js',
        );
        final arguments = <String, Object?>{};
        if (target == 'cg') {
          final direct = Uri.parse(WebVPN.unwrap(_currentUri.toString()));
          final entry = direct.replace(
            path: '/assignment/index.jsp',
            query: '',
            fragment: '',
          );
          arguments['rootURL'] = state.browserURL(entry.toString());
          arguments['originalRootURL'] = entry.toString();
        }
        if (target == 'card') arguments['month'] = state.cardQueryMonth;
        if (!current()) return;
        final report = await _bridge.run(script, arguments);
        if (!current()) return;
        switch (target) {
          case 'cg':
            state.acceptCGReport(report);
          case 'grades':
            state.acceptGradeReport(GradeReport.fromBrowser(report));
          case 'card':
            state.acceptCardReport(report);
        }
      }
      if (mounted && current()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同步完成，可返回查看数据与读取提示')));
      }
    } catch (e) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      client?.dispose();
      if (identical(_learningClient, client)) _learningClient = null;
      if (current()) {
        setState(() {
          _syncing = false;
          _syncProgress = '';
        });
      }
    }
  }

  Future<void> _menuAction(String action) async {
    switch (action) {
      case 'refresh':
        await _load(_currentUri);
      case 'http':
        final alternative = PortalWebPolicy.httpAlternative(_currentUri);
        if (alternative != null) await _load(alternative);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _currentUri.toString()));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前链接已复制')));
        }
      case 'browser':
        await _openExternal(_currentUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (_pageTitle.isEmpty ? widget.title : _pageTitle)
        .replaceFirst(RegExp(r'-\s*东北大学.*$'), '')
        .trim();
    final alternative = PortalWebPolicy.httpAlternative(_currentUri);
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) smartBack();
      },
      child: Scaffold(
        appBar: PageAppBar(
          title: title,
          leading: isApple
              ? Tooltip(
                  message: '关闭页面',
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      CupertinoIcons.back,
                      size: 24,
                      color: IosColors.label(
                          Theme.of(context).brightness == Brightness.dark),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: '关闭页面',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          actions: [
            if (_dataTarget != null)
              IconButton(tooltip: '同步到应用', onPressed: _syncing ? null : _syncData,
                icon: _syncing ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync)),
            if (widget.loginMode)
              IconButton(
                tooltip: '诊断日志',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: _showDiagLog,
              ),
            if (isApple)
              Tooltip(
                message: _desktop ? '切换手机版' : '切换桌面版',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: _toggleDesktop,
                  child: Icon(
                    _desktop
                        ? CupertinoIcons.device_phone_portrait
                        : CupertinoIcons.device_laptop,
                    size: 20,
                    color: _desktop
                        ? scheme.primary
                        : IosColors.label(
                            Theme.of(context).brightness == Brightness.dark),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: _desktop ? '切换手机版' : '切换桌面版',
                icon: Icon(
                  _desktop ? Icons.smartphone : Icons.desktop_windows_outlined,
                  size: 22,
                ),
                onPressed: _toggleDesktop,
              ),
            if (isApple)
              Tooltip(
                message: '浏览选项',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: () => _showSafariOptions(context),
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: IosColors.label(
                        Theme.of(context).brightness == Brightness.dark),
                  ),
                ),
              )
            else
              PopupMenuButton<String>(
                tooltip: '浏览选项',
                icon: const Icon(Icons.more_horiz),
                onSelected: _menuAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'refresh', child: Text('重新加载')),
                  const PopupMenuItem(value: 'copy', child: Text('复制当前链接')),
                  const PopupMenuItem(value: 'browser', child: Text('用系统浏览器打开')),
                  if (alternative != null)
                    const PopupMenuItem(
                      value: 'http',
                      child: Text('使用 HTTP 打开（校内旧系统）'),
                    ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: _buildLiquidBottomBar(context),
        body: Column(
          children: [
            _buildAddressBar(context),
            if (_dataTarget != null)
              Material(color: scheme.secondaryContainer, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  Expanded(child: Text(_syncing ? _syncProgress : '完成网页登录后，同步${_dataTarget == 'card' ? '余额与所选月流水' : _dataTarget == 'grades' ? '全部学期成绩' : '全部课程作业'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (_syncing) TextButton(onPressed: () => setState(_cancelSync), child: const Text('取消'))
                  else TextButton(onPressed: _syncData, child: const Text('同步')),
                ]),
              )),
            if (_needLogin) _buildSessionExpiredBanner(context),
            _buildProgressBar(context),
            Expanded(
              child: Stack(
                children: [
                  if (_viewReady)
                    WebViewWidget(controller: _controller)
                  else
                    _buildSkeletonPlaceholder(context),
                  if (_error != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.surface,
                        child: _ErrorView(
                          message: _error!,
                          onRetry: () => _load(_currentUri),
                          onBrowser: () => _openExternal(_currentUri),
                          onHttp: alternative == null
                              ? null
                              : () => _load(alternative),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFFAFAFA),
      child: Center(
        child: isApple
            ? const CupertinoActivityIndicator(radius: 12)
            : CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
      ),
    );
  }

  Widget _buildAddressBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isHttps = _currentUri.scheme == 'https';
    final hostText =
        _currentUri.host.isEmpty ? 'about:blank' : _currentUri.host;

    final capsuleContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHttps
                ? (isApple ? CupertinoIcons.lock_fill : Icons.lock)
                : (isApple
                    ? CupertinoIcons.exclamationmark_shield
                    : Icons.security_update_warning),
            size: 13,
            color: isHttps
                ? (isApple
                    ? CupertinoColors.secondaryLabel.resolveFrom(context)
                    : scheme.onSurfaceVariant)
                : scheme.error,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isHttps ? hostText : 'HTTP · $hostText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isHttps ? scheme.onSurface : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );

    final Widget capsule;
    if (isApple) {
      capsule = Container(
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: CupertinoColors.separator
                .resolveFrom(context)
                .withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: capsuleContent,
      );
    } else {
      capsule = Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
        child: capsuleContent,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      alignment: Alignment.center,
      child: capsule,
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: _progressNotifier,
      builder: (context, progress, _) {
        if (progress >= 1.0 || _error != null) {
          return const SizedBox(height: 2.5);
        }
        return SizedBox(
          height: 2.5,
          child: Stack(
            children: [
              Container(
                color: isApple
                    ? Colors.transparent
                    : scheme.primary.withValues(alpha: 0.1),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.04, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary,
                        scheme.tertiary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSessionExpiredBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: isApple
          ? IosGlassSurface(
              radius: 14,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      size: 20,
                      color: CupertinoColors.systemOrange.resolveFrom(context),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '统一认证会话已失效',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _goToLogin,
                      child: const Text(
                        '去登录',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Material(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                title: const Text('统一认证会话已失效'),
                trailing: TextButton(
                  onPressed: _goToLogin,
                  child: const Text('去登录'),
                ),
              ),
            ),
    );
  }

  Widget _buildLiquidBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isApple ? CupertinoColors.label.resolveFrom(context) : scheme.onSurface;
    final disabledColor = isApple
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : scheme.onSurface.withValues(alpha: 0.35);

    Widget navButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      bool active = false,
      double size = 20,
    }) {
      final enabled = onPressed != null;
      final c = active
          ? scheme.primary
          : enabled
              ? iconColor
              : disabledColor;

      return isApple
          ? Tooltip(
              message: tooltip,
              child: CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(40, 40),
                onPressed: onPressed,
                child: Icon(icon, size: size, color: c),
              ),
            )
          : IconButton(
              tooltip: tooltip,
              icon: Icon(icon, size: size, color: c),
              onPressed: onPressed,
            );
    }

    final toolbar = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          navButton(
            tooltip: '后退',
            icon: isApple
                ? CupertinoIcons.chevron_left
                : Icons.arrow_back_ios_new,
            onPressed: _canGoBack ? smartBack : null,
            size: 20,
          ),
          navButton(
            tooltip: '前进',
            icon: isApple
                ? CupertinoIcons.chevron_right
                : Icons.arrow_forward_ios,
            onPressed: _canGoForward ? _goForward : null,
            size: 20,
          ),
          navButton(
            tooltip: '重新加载',
            icon: isApple ? CupertinoIcons.arrow_clockwise : Icons.refresh,
            onPressed: () => _load(_currentUri),
            size: 21,
          ),
          navButton(
            tooltip: _desktop ? '切换手机版' : '切换桌面版',
            icon: _desktop
                ? (isApple
                    ? CupertinoIcons.device_phone_portrait
                    : Icons.smartphone)
                : (isApple
                    ? CupertinoIcons.device_laptop
                    : Icons.desktop_windows_outlined),
            onPressed: _toggleDesktop,
            active: _desktop,
            size: 21,
          ),
          navButton(
            tooltip: '更多选项',
            icon: isApple ? CupertinoIcons.ellipsis : Icons.more_horiz,
            onPressed: () => _showSafariOptions(context),
            size: 22,
          ),
        ],
      ),
    );

    if (isApple) {
      return IosGlassSurface(
        radius: 0,
        border: Border(
          top: BorderSide(
            color: IosColors.separator(dark).withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: SafeArea(
          top: false,
          child: toolbar,
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: toolbar,
      ),
    );
  }

  void _showDiagLog() {
    final text = _diagLog.isEmpty ? '（暂无记录）' : _diagLog.join('\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录链路诊断日志'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('日志已复制，请发给开发者')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制全部'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showSafariOptions(BuildContext context) {
    final alternative = PortalWebPolicy.httpAlternative(_currentUri);
    if (isApple) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(_currentUri.toString()),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _menuAction('refresh');
              },
              child: const Text('重新加载'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _menuAction('copy');
              },
              child: const Text('复制当前链接'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _menuAction('browser');
              },
              child: const Text('用系统浏览器打开'),
            ),
            if (alternative != null)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _menuAction('http');
                },
                child: const Text('使用 HTTP 打开（校内旧系统）'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新加载'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _menuAction('refresh');
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制当前链接'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _menuAction('copy');
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('用系统浏览器打开'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _menuAction('browser');
                },
              ),
              if (alternative != null)
                ListTile(
                  leading: const Icon(Icons.http),
                  title: const Text('使用 HTTP 打开（校内旧系统）'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _menuAction('http');
                  },
                ),
            ],
          ),
        ),
      );
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBrowser,
    this.onHttp,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBrowser;
  final VoidCallback? onHttp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardContent = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isApple ? CupertinoIcons.wifi_exclamationmark : Icons.cloud_off,
              size: 40,
              color: scheme.error,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          AdaptiveFilledButton(onPressed: onRetry, child: const Text('重试')),
          if (onHttp != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onHttp,
              child: const Text('使用 HTTP 打开（校内旧系统）'),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(onPressed: onBrowser, child: const Text('改用系统浏览器打开')),
        ],
      ),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: isApple
            ? IosGlassSurface(
                radius: Ds.rLg,
                child: cardContent,
              )
            : Card(child: cardContent),
      ),
    );
  }
}
