/// 读取系统 WebView 的持久化会话 Cookie。
///
/// iOS: WKHTTPCookieStore（HttpOnly 含 CASTGC / SESS_ID / 网关票据）；
/// Android: 全局 CookieManager。网页登录的会话存在 WebView 的
/// 默认持久化存储里，重启后依然有效，可据此免密码恢复登录。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'webvpn.dart';

/// 捕获系统 WebView 中指定站点相关的全部 Cookie。
Future<List<WebViewCookie>> captureWebViewCookies(Uri uri) async {
  try {
    if (kIsWeb) return const [];
    // 使用实际 WebView 引擎，不能让用户选择的界面风格决定 Cookie 存储。
    final cookies = await WebViewCookieManager().getCookies(domain: uri);
    return cookies.map((c) {
      // Android 插件返回的 domain 是完整请求 URL；HTTP Cookie 罐需要主机名。
      final domain = Uri.tryParse(c.domain);
      return WebViewCookie(
        name: c.name,
        value: c.value,
        domain: domain != null && domain.hasScheme && domain.host.isNotEmpty
            ? domain.host
            : c.domain,
        path: c.path,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
}

/// 汇总登录相关 Cookie（含网关代理路径，按 name+domain+path 去重）。
Future<List<WebViewCookie>> captureWebLoginCookies() async {
  final out = <WebViewCookie>[];
  final seen = <String>{};
  for (final uri in [
    Uri.parse('https://pass.neu.edu.cn/tpass/login'),
    Uri.parse('https://personal.neu.edu.cn/portal'),
    Uri.parse('https://webvpn.neu.edu.cn/'),
    Uri.parse('https://portal.neu.edu.cn/tp_up/'),
    Uri.parse(WebVPN.wrap('https://personal.neu.edu.cn/portal')),
  ]) {
    for (final c in await captureWebViewCookies(uri)) {
      final key = '${c.domain}|${c.path}|${c.name}';
      if (c.name.isEmpty || c.value.isEmpty || !seen.add(key)) continue;
      out.add(c);
    }
  }
  return out;
}

/// 清空系统 WebView 的全部 Cookie（退出登录时调用，确保网页登录会话一并失效）。
Future<void> clearWebViewCookies() async {
  try {
    if (kIsWeb) return;
    await WebViewCookieManager().clearCookies();
  } catch (_) {}
}
