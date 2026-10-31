/// 应用内浏览器 v2：注入 CAS 会话、站点历史返回、桌面版切换、
/// 进度条、出错自动换协议重试、复制链接 / 系统浏览器兜底。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_state.dart';
import '../core/cas_crypto.dart';
import 'login_page.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  double _progress = 0;
  String? _error;
  String _pageTitle = '';
  bool _needLogin = false;
  int _casAttempts = 0;
  bool _altSchemeTried = false;
  bool _desktop = false;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(_mobileUa)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mountedSet(() => _progress = p / 100),
        onPageFinished: (_) => _onPageSettled(),
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) {
            final uri = Uri.tryParse(widget.url);
            final scheme = uri?.scheme ?? 'https';
            if (!_altSchemeTried) {
              // 校内老系统多为 http-only，https 失败自动降级（反之亦然）
              _altSchemeTried = true;
              final altScheme = scheme == 'https' ? 'http' : 'https';
              final altUrl =
                  widget.url.replaceFirst('$scheme://', '$altScheme://');
              _controller.loadRequest(Uri.parse(altUrl));
              return;
            }
            mountedSet(() => _error = '加载失败（${e.errorCode}）：'
                '可能需要校园网 / VPN，或该系统不支持内嵌打开');
          }
        },
      ));
    _injectCookiesThenLoad();
  }

  bool _isCasLoginPage(String url) =>
      url.contains('pass.neu.edu.cn') && url.contains('/tpass/login');

  Future<void> _onPageSettled() async {
    String url = '';
    try {
      url = await _controller.currentUrl() ?? '';
    } catch (_) {}
    try {
      final back = await _controller.canGoBack();
      mountedSet(() {
        _progress = 1;
        _canGoBack = back;
      });
    } catch (_) {}
    try {
      final t = await _controller.getTitle();
      if (t != null && t.trim().isNotEmpty) {
        mountedSet(() => _pageTitle = t);
      }
    } catch (_) {}
    if (_isCasLoginPage(url)) {
      final ok = await _autoCasLogin();
      if (!ok) mountedSet(() => _needLogin = true);
    } else {
      mountedSet(() => _needLogin = false);
    }
  }

  /// CAS 登录页出现时：有保存的凭证就自动填表提交（RSA 与官网一致），无感重登。
  Future<bool> _autoCasLogin() async {
    if (_casAttempts >= 2) return false;
    final s = AppScope.of(context);
    final creds = await s.storedCredentials();
    if (creds == null) return false;
    _casAttempts++;
    try {
      String str(Object? o) => (o?.toString() ?? '')
          .replaceAll('"', '')
          .replaceAll("'", '')
          .trim();
      final lt = str(await _controller.runJavaScriptReturningResult(
          "document.getElementById('lt')?.value || ''"));
      final execution = str(await _controller.runJavaScriptReturningResult(
          "document.getElementsByName('execution')[0]?.value || ''"));
      if (lt.isEmpty || execution.isEmpty) return false;
      final rsa = CasCrypto.encrypt(creds.$1 + creds.$2);
      await _controller.runJavaScript("""
        (function(){
          var f = document.getElementById('rsa'); if (f) f.value = '$rsa';
          var u = document.getElementById('ul'); if (u) u.value = '${creds.$1.length}';
          var p = document.getElementById('pl'); if (p) p.value = '${creds.$2.length}';
          var l = document.getElementById('lt'); if (l) l.value = '$lt';
          var e = document.getElementsByName('execution')[0]; if (e) e.value = '$execution';
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
      final s = AppScope.of(context);
      if (s.mode == SessionMode.live) {
        final manager = WebViewCookieManager();
        for (final entry in s.cookieSnapshot().entries) {
          for (final kv in entry.value.entries) {
            await manager.setCookie(WebViewCookie(
              name: kv.key,
              value: kv.value,
              domain: entry.key,
              path: '/',
            ));
          }
        }
      }
    } catch (_) {
      // 未登录 / cookie 不可用也能打开（系统可能要求自行登录）
    }
    if (mounted) {
      final uri = Uri.tryParse(widget.url) ??
          Uri.parse(Uri.encodeFull(widget.url));
      _controller.loadRequest(uri);
    }
  }

  void mountedSet(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// 返回策略：优先退站点历史；若历史回退后 URL 没变（SPA 标签页等），
  /// 视为无有效历史，直接退出页面。
  Future<void> smartBack() async {
    try {
      final cur = await _controller.currentUrl() ?? '';
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        final after = await _controller.currentUrl() ?? '';
        if (after != cur) return; // 确实回退到了上一个页面
      }
    } catch (_) {}
    // PopScope(canPop:false) 会拦截 maybePop，必须用 pop() 强制退出
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleDesktop() async {
    HapticFeedback.selectionClick();
    mountedSet(() {
      _desktop = !_desktop;
      _casAttempts = 0;
      _altSchemeTried = false;
      _error = null;
      _progress = 0;
    });
    await _controller.setUserAgent(_desktop ? _desktopUa : _mobileUa);
    _controller.reload();
  }

  Future<void> _reloadAll() async {
    mountedSet(() {
      _casAttempts = 0;
      _altSchemeTried = false;
      _error = null;
      _progress = 0;
    });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownTitle = (_pageTitle.isNotEmpty ? _pageTitle : widget.title)
        .replaceFirst(RegExp(r'-\s*东北大学.*$'), '')
        .trim();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) smartBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _canGoBack ? '返回上一页' : '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: smartBack,
          ),
          title: Text(shownTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: _desktop ? '切换手机版' : '切换桌面版',
              icon: Icon(
                _desktop ? Icons.smartphone : Icons.desktop_windows_outlined,
                size: 22,
                color: _desktop ? scheme.primary : null,
              ),
              onPressed: _toggleDesktop,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 22),
              onSelected: (v) async {
                switch (v) {
                  case 'refresh':
                    await _reloadAll();
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: widget.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('链接已复制')));
                    }
                  case 'browser':
                    launchUrl(Uri.parse(widget.url),
                        mode: LaunchMode.externalApplication);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('重新加载'),
                        dense: true,
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                        leading: Icon(Icons.link),
                        title: Text('复制链接'),
                        dense: true,
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'browser',
                    child: ListTile(
                        leading: Icon(Icons.open_in_new),
                        title: Text('用系统浏览器打开'),
                        dense: true,
                        contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_needLogin)
              Material(
                color: scheme.tertiaryContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '统一认证登录态已失效，登录后即可免登录使用各系统',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onTertiaryContainer),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final appState = AppScope.of(context);
                          await nav.push(MaterialPageRoute(
                              builder: (_) => const LoginPage()));
                          if (!mounted) return;
                          if (appState.mode == SessionMode.live) {
                            mountedSet(() {
                              _needLogin = false;
                              _casAttempts = 0;
                              _altSchemeTried = false;
                              _progress = 0;
                            });
                            await _injectCookiesThenLoad();
                          }
                        },
                        child: const Text('去登录'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error == null && _progress < 1)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2.5,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            Expanded(
              child: _error != null
                  ? _ErrorView(
                      message: _error!,
                      url: widget.url,
                      onRetry: () => mountedSet(() {
                        _error = null;
                        _altSchemeTried = false;
                        _progress = 0;
                        _controller.reload();
                      }))
                  : Stack(
                      children: [
                        WebViewWidget(controller: _controller),
                        // 首帧前铺底色，避免白闪
                        if (_progress < 0.05)
                          ColoredBox(
                            color: scheme.surface,
                            child: const SizedBox.expand(),
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
    required this.url,
    required this.onRetry,
  });

  final String message;
  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: scheme.outline),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              child: const Text('改用系统浏览器打开'),
            ),
          ],
        ),
      ),
    );
  }
}
