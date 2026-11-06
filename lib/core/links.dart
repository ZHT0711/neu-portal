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
import 'app_state.dart';
import 'web_policy.dart';
import '../pages/webview_page.dart';

class AppLinks {
  AppLinks._();

  static bool get supportsDataSync => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 规范化链接：
  /// - 去空白、去首尾引号
  /// - 无协议头时自动补全（校内系统多为 http；IP 直连/带端口的一律 http）
  static String normalize(String raw) => PortalWebPolicy.normalize(raw);

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
    if (url.isEmpty || !PortalWebPolicy.isWebUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('该应用未提供有效链接${rawUrl.trim().isEmpty ? '' : '：$rawUrl'}')),
        );
      }
      return;
    }
    final state = AppScope.of(context);
    final useWeb =
        kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!useWeb) {
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebViewPage(title: title, url: url),
          ),
        );
        return;
      }
    }
    await state.prepareBrowserAccess(force: true);
    final target = Uri.parse(state.browserURL(url));
    final ok = await launchUrl(
      target,
      mode: LaunchMode.inAppBrowserView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
    if (!ok) await launchUrl(target, mode: LaunchMode.externalApplication);
  }
}
