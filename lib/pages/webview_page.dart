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
import '../core/platform_style.dart';
import '../core/web_policy.dart';
import 'login_page.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.title, required this.url});
  final String title;
  final String url;
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  late Uri _currentUri;
  double _progress = 0;
  String? _error;
  String _pageTitle = '';
  bool _needLogin = false;
  int _casAttempts = 0;
  bool _desktop = false;
  bool _canGoBack = false;
  final _httpRetriedOrigins = <String>{};

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
    _configureAndLoad();
  }

  Future<void> _configureAndLoad() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(const Color(0x00000000));
      await _controller.setUserAgent(
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
            _rememberUrl(url);
            mountedSet(() {
              _error = null;
              _progress = 0;
            });
          },
          onProgress: (value) => mountedSet(() => _progress = value / 100),
          onPageFinished: (_) => _onPageSettled(),
          onWebResourceError: (error) {
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
      final title = await _controller.getTitle();
      mountedSet(() {
        _progress = 1;
        _canGoBack = back;
        if (title != null && title.trim().isNotEmpty) _pageTitle = title;
      });
    } catch (_) {
      /* A page can disappear while the user navigates back. */
    }
    if (!mounted) return;
    if (PortalWebPolicy.isCasLogin(_currentUri)) {
      final ok = await _autoCasLogin();
      if (!ok) mountedSet(() => _needLogin = true);
    } else {
      mountedSet(() => _needLogin = false);
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
      if (state.mode == SessionMode.live) {
        final manager = WebViewCookieManager();
        for (final entry in state.cookieSnapshot().entries) {
          for (final cookie in entry.value.entries) {
            await manager.setCookie(
              WebViewCookie(
                name: cookie.key,
                value: cookie.value,
                domain: entry.key,
                path: '/',
              ),
            );
          }
        }
      }
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
    mountedSet(() {
      _currentUri = uri;
      _error = null;
      _progress = 0;
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
          leading: IconButton(
            tooltip: _canGoBack ? '返回上一页' : '返回',
            icon: Icon(isApple ? CupertinoIcons.back : Icons.arrow_back),
            onPressed: smartBack,
          ),
          actions: [
            IconButton(
              tooltip: _desktop ? '切换手机版' : '切换桌面版',
              icon: Icon(
                _desktop ? Icons.smartphone : Icons.desktop_windows_outlined,
                size: 22,
              ),
              onPressed: _toggleDesktop,
            ),
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
        body: Column(
          children: [
            if (_needLogin)
              Material(
                color: scheme.tertiaryContainer,
                child: ListTile(
                  title: const Text('统一认证会话已失效'),
                  trailing: TextButton(
                    child: const Text('去登录'),
                    onPressed: () async {
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
                    },
                  ),
                ),
              ),
            if (_currentUri.scheme == 'http')
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HTTP · ${_currentUri.host}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (_error == null && _progress < 1)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2,
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
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
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          AdaptiveFilledButton(onPressed: onRetry, child: const Text('重试')),
          if (onHttp != null)
            TextButton(
              onPressed: onHttp,
              child: const Text('使用 HTTP 打开（校内旧系统）'),
            ),
          TextButton(onPressed: onBrowser, child: const Text('改用系统浏览器打开')),
        ],
      ),
    ),
  );
}
