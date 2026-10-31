/// URL and browser compatibility rules, independent of platform plugins.
library;

abstract final class PortalWebPolicy {
  static String normalize(String raw) {
    var value = raw.trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      value = value.substring(1);
    }
    if (value.endsWith('"') || value.endsWith("'")) {
      value = value.substring(0, value.length - 1);
    }
    value = value.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('//')) return 'https:$value';
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value) &&
        !RegExp(r'^[^/:]+:\d+(?:/|$)').hasMatch(value)) {
      return value;
    }
    final authority = value.split('/').first;
    final local =
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}(?::\d+)?$').hasMatch(authority) ||
        RegExp(r':\d+$').hasMatch(authority);
    return '${local ? 'http' : 'https'}://$value';
  }

  static bool isWebUrl(Uri? uri) =>
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  // Credentials may only be injected into the actual HTTPS CAS origin.
  static bool isCasLogin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host.toLowerCase() == 'pass.neu.edu.cn' &&
      uri.port == 443 &&
      (uri.path == '/tpass/login' || uri.path == '/tpass/login/');

  /// HTTP compatibility retry for campus services; identity origins stay on HTTPS.
  static Uri? httpAlternative(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
    final host = uri.host.toLowerCase();
    if ({
      'pass.neu.edu.cn',
      'personal.neu.edu.cn',
      'webvpn.neu.edu.cn',
    }.contains(host)) {
      return null;
    }
    final parts = host.split('.').map(int.tryParse).toList();
    final address =
        parts.length == 4 &&
        parts.every((part) => part != null && part >= 0 && part <= 255);
    final campusIp =
        address &&
        (parts[0] == 10 ||
            (parts[0] == 210 && parts[1] == 30) ||
            (parts[0] == 219 && parts[1] == 216) ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31));
    final campus =
        host == 'neu.edu.cn' || host.endsWith('.neu.edu.cn') || campusIp;
    return campus
        ? uri.replace(scheme: 'http', port: uri.port == 443 ? 80 : uri.port)
        : null;
  }

  static bool isExternalApp(Uri uri) => const {
    'tel',
    'mailto',
    'sms',
    'weixin',
    'alipay',
    'alipays',
    'dingtalk',
    'mqq',
    'mqqapi',
    'wework',
    'wemeet',
    'intent',
  }.contains(uri.scheme);

  // WKWebView's default UA identifies the real iPhone/iPad and WebKit version.
  static String? userAgent({required bool ios, required bool desktop}) {
    if (ios && !desktop) return null;
    if (ios) {
      return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
    }
    return desktop
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
        : 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  }
}
