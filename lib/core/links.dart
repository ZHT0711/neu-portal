/// 统一的“打开链接”入口。
///
/// 手机端：应用内 WebView，注入 CAS 会话 Cookie —— 各业务系统经 SSO 跳转
/// 免登录直达，配合进度条比拉起外部浏览器快得多。
/// 桌面 / Web：Custom Tabs / 系统默认浏览器（inAppBrowserView 冷启动更快）。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import '../pages/webview_page.dart';

class AppLinks {
  AppLinks._();

  /// 规范化链接：
  /// - 去空白、去首尾引号
  /// - 无协议头时自动补全（校内系统多为 http；IP 直连/带端口的一律 http）
  static String normalize(String raw) {
    var u = raw.trim();
    if (u.startsWith('"') || u.startsWith("'")) {
      u = u.substring(1);
    }
    if (u.endsWith('"') || u.endsWith("'")) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) return u;
    final schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
    if (schemeRe.hasMatch(u)) return u;
    // 校内老系统基本都是 http；对外网站默认 https
    final looksLikeIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}').hasMatch(u);
    final hasPort = RegExp(r':\d+').hasMatch(u.split('/').first);
    final intranet = looksLikeIp || hasPort || u.startsWith('10.');
    u = (intranet ? 'http://' : 'https://') + u;
    return u;
  }

  /// 打开一个门户应用（自动选择最佳入口：mobile → url → mimipath）。
  static Future<void> openApp(BuildContext context, PortalApp app) {
    return open(context, app.entryUrl(), title: app.name);
  }

  /// 打开门户相关链接。
  static Future<void> open(
    BuildContext context,
    String rawUrl, {
    String title = '页面',
  }) async {
    final url = normalize(rawUrl);
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('该应用未提供有效链接${rawUrl.trim().isEmpty ? '' : '：$rawUrl'}')),
        );
      }
      return;
    }
    final useWeb = kIsWeb ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS;
    if (!useWeb) {
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WebViewPage(title: title, url: uri.toString()),
        ));
        return;
      }
    }
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
    if (!ok) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
