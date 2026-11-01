/// 读取系统 WebView 的持久化会话 Cookie。
///
/// iOS: WKHTTPCookieStore（HttpOnly 含 CASTGC / SESS_ID / 网关票据）；
/// Android: 全局 CookieManager。网页登录的会话存在 WebView 的
/// 默认持久化存储里，重启后依然有效，可据此免密码恢复登录。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'platform_style.dart';

/// 捕获系统 WebView 中指定站点相关的全部 Cookie。
Future<List<WebViewCookie>> captureWebViewCookies(Uri uri) async {
  try {
    if (kIsWeb) return const [];
    if (isApple) {
      final manager =
          WebKitWebViewCookieManager(WebKitWebViewCookieManagerCreationParams());
      return await manager.getCookies(uri);
    }
    final manager = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    return await manager.getCookies(uri);
  } catch (_) {
    return const [];
  }
}

/// 汇总四个校内域名的 WebView Cookie（去重按 name+domain）。
Future<List<WebViewCookie>> captureWebLoginCookies() async {
  final out = <WebViewCookie>[];
  final seen = <String>{};
  for (final uri in [
    Uri.parse('https://pass.neu.edu.cn/tpass/login'),
    Uri.parse('https://personal.neu.edu.cn/portal'),
    Uri.parse('https://webvpn.neu.edu.cn/'),
    Uri.parse('https://portal.neu.edu.cn/tp_up/'),
  ]) {
    for (final c in await captureWebViewCookies(uri)) {
      final key = '${c.domain}|${c.name}';
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
