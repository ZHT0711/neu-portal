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
import '../core/platform_style.dart';
import '../core/theme.dart';
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
  bool _canGoForward = false;
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
      bool forward = false;
      try {
        forward = await _controller.canGoForward();
      } catch (_) {}
      final title = await _controller.getTitle();
      mountedSet(() {
        _progress = 1;
        _canGoBack = back;
        _canGoForward = forward;
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
                  message: _canGoBack ? '返回上一页' : '返回',
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: smartBack,
                    child: Icon(
                      CupertinoIcons.back,
                      size: 24,
                      color: IosColors.label(
                          Theme.of(context).brightness == Brightness.dark),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: _canGoBack ? '返回上一页' : '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: smartBack,
                ),
          actions: [
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
            if (_needLogin) _buildSessionExpiredBanner(context),
            if (_error == null && _progress < 1)
              _buildProgressBar(context),
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
      capsule = IosGlassSurface(
        radius: 12,
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
            widthFactor: _progress.clamp(0.04, 1.0),
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
