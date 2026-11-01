/// Native cookie APIs preserve HttpOnly, Secure, expiry and duplicate paths.
library;

import 'package:flutter/services.dart';
import 'webvpn.dart';

const _channel = MethodChannel('neu.portal/session_cookies');

Future<List<Map<String, dynamic>>?> readNativeSessionCookies() async {
  try {
    final values = await _channel.invokeListMethod<dynamic>('read', [
      'https://pass.neu.edu.cn/',
      'https://pass.neu.edu.cn/tpass/login',
      'https://personal.neu.edu.cn/',
      'https://personal.neu.edu.cn/portal',
      'https://webvpn.neu.edu.cn/',
      'https://portal.neu.edu.cn/tp_up/',
      WebVPN.wrap('https://personal.neu.edu.cn/portal'),
    ]);
    return values
        ?.whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
  } on MissingPluginException {
    return null;
  }
}

Future<void> restoreNativeSessionCookies(
  List<Map<String, dynamic>> cookies,
) async {
  try {
    await _channel.invokeMethod<void>('restore', cookies);
  } on MissingPluginException {
    // Desktop/test hosts have no WebView. Mobile builds register this channel.
  }
}

String sessionCookieKey(Map<String, dynamic> c) =>
    '${'${c['domain']}'.replaceFirst(RegExp(r'^\.'), '')}|${c['path']}|${c['name']}';
