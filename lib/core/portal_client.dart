/// 一号通门户客户端：CAS 登录 + 各业务接口。
/// 手动重定向 + RFC 规范 Cookie 罐，保证 CASTGC / SESS_ID 全程正确跨域传递。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'cas_crypto.dart';
import 'models.dart';
import 'grade_report.dart';
import 'webvpn.dart';

enum AccessMode { auto, direct, webvpn }

class PortalException implements Exception {
  final String message;
  final bool sessionExpired;
  PortalException(this.message, {this.sessionExpired = false});
  @override
  String toString() => message;
}

/// 统一认证要求新设备短信二次认证（图形码 + 短信，login_second.js 流程）。
class SecondAuthRequired implements Exception {
  final String message;
  SecondAuthRequired(this.message);
  @override
  String toString() => message;
}

class _CookieEntry {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool hostOnly;
  final bool httpOnly;
  final bool metadataKnown;

  _CookieEntry({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expires,
    this.secure = false,
    this.hostOnly = false,
    this.httpOnly = false,
    this.metadataKnown = true,
  });

  bool get isExpired {
    if (expires != null && DateTime.now().isAfter(expires!)) return true;
    return false;
  }
}

class CookieJar {
  /// domain/host -> (cookie name -> _CookieEntry)
  final Map<String, Map<String, _CookieEntry>> _store = {};

  static List<String> splitSetCookie(String raw) => raw
      .split(RegExp(r',(?=\s*[^\s=;,]+\s*=)'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  void absorb(Uri uri, http.StreamedResponse resp) {
    absorbRaw(uri, resp.headers['set-cookie']);
  }

  void absorbRaw(Uri uri, String? sc, {bool metadataKnown = true}) {
    if (sc == null || sc.isEmpty) return;

    for (final rawCookie in splitSetCookie(sc)) {
      final parts = rawCookie.split(';');
      if (parts.isEmpty) continue;

      final first = parts[0].trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (name.isEmpty) continue;

      var domain = uri.host.toLowerCase();
      var path = '/';
      var hostOnly = true;
      var secure = false;
      var httpOnly = false;
      int? maxAge;
      DateTime? expires;
      var expired = value.isEmpty;

      for (var i = 1; i < parts.length; i++) {
        final attr = parts[i].trim();
        final attrEq = attr.indexOf('=');
        final attrName =
            (attrEq > 0 ? attr.substring(0, attrEq) : attr).trim().toLowerCase();
        final attrVal = attrEq > 0 ? attr.substring(attrEq + 1).trim() : '';

        if (attrName == 'domain' && attrVal.isNotEmpty) {
          hostOnly = false;
          domain = attrVal.toLowerCase();
          if (domain.startsWith('.')) domain = domain.substring(1);
        } else if (attrName == 'path' && attrVal.isNotEmpty) {
          path = attrVal;
        } else if (attrName == 'secure') {
          secure = true;
        } else if (attrName == 'httponly') {
          httpOnly = true;
        } else if (attrName == 'expires') {
          try { expires = parseHttpDate(attrVal); } catch (_) {}
        } else if (attrName == 'max-age') {
          final sec = int.tryParse(attrVal);
          maxAge = sec;
          if (sec != null) {
            if (sec <= 0) {
              expired = true;
            } else {
              expires = DateTime.now().add(Duration(seconds: sec));
            }
          }
        }
      }

      // Max-Age takes precedence regardless of attribute order.
      if (maxAge != null && maxAge > 0) {
        expires = DateTime.now().add(Duration(seconds: maxAge));
      }
      expired = expired || (expires?.isBefore(DateTime.now()) ?? false);

      if (!_matchesDomain(uri.host, domain)) continue;
      final key = '$path\u0000$name';
      final domainStore = _store.putIfAbsent(domain, () => {});
      if (expired) {
        domainStore.remove(key);
      } else {
        domainStore[key] = _CookieEntry(
          name: name,
          value: value,
          domain: domain,
          path: path,
          expires: expires,
          secure: secure,
          hostOnly: hostOnly,
          httpOnly: httpOnly,
          metadataKnown: metadataKnown,
        );
      }
    }
  }

  bool _matchesDomain(String host, String domain) {
    final h = host.toLowerCase();
    final d = domain.toLowerCase();
    if (h == d) return true;
    if (h.endsWith('.$d')) return true;
    return false;
  }

  void clear() => _store.clear();

  List<Map<String, dynamic>> sessionCookies() => [
    for (final domain in _store.values)
      for (final c in domain.values)
        if (!c.isExpired)
          {
            'name': c.name,
            'value': c.value,
            'domain': c.domain,
            'path': c.path,
            'secure': c.secure,
            'httpOnly': c.httpOnly,
            'hostOnly': c.hostOnly,
            'metadataKnown': c.metadataKnown,
            'expires': c.expires?.millisecondsSinceEpoch,
          },
  ];

  void restoreSessionCookies(List<Map<String, dynamic>> cookies) {
    for (final j in cookies) {
      final domain = '${j['domain'] ?? ''}'.toLowerCase().replaceFirst(
        RegExp(r'^\.'),
        '',
      );
      final name = '${j['name'] ?? ''}', value = '${j['value'] ?? ''}';
      final path = '${j['path'] ?? '/'}';
      if (!(domain == 'neu.edu.cn' || domain.endsWith('.neu.edu.cn')) ||
          name.isEmpty ||
          value.isEmpty ||
          !path.startsWith('/')) {
        continue;
      }
      final expiry = j['expires'];
      final c = _CookieEntry(
        name: name,
        value: value,
        domain: domain,
        path: path,
        secure: j['secure'] == true,
        httpOnly: j['httpOnly'] == true,
        hostOnly: j['hostOnly'] == true,
        metadataKnown: j['metadataKnown'] != false,
        expires: expiry is num
            ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt())
            : null,
      );
      if (!c.isExpired) {
        _store.putIfAbsent(domain, () => {})['$path\u0000$name'] = c;
      }
    }
  }

  String? headerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final matches = <_CookieEntry>[];
    for (final entry in _store.entries) {
      for (final cookie in entry.value.values) {
        final domainOK =
            host == cookie.domain ||
            (!cookie.hostOnly && _matchesDomain(host, cookie.domain));
        final pathOK =
            path == cookie.path ||
            (path.startsWith(cookie.path) &&
                (cookie.path.endsWith('/') ||
                    path.substring(cookie.path.length).startsWith('/')));
        if (domainOK &&
            pathOK &&
            !cookie.isExpired &&
            (!cookie.secure || uri.scheme == 'https')) {
          matches.add(cookie);
        }
      }
    }
    matches.sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.isEmpty
        ? null
        : matches.map((c) => '${c.name}=${c.value}').join('; ');
  }

  bool hasCookie(Uri uri, String name) =>
      headerFor(uri)?.split('; ').any((pair) => pair.startsWith('$name=')) ??
      false;

  List<({String name, String value, String domain, String path})>
  browserCookies() => [
    for (final domain in _store.values)
      for (final c in domain.values)
        if (!c.isExpired)
          (
            name: c.name,
            value: c.value,
            domain: c.hostOnly ? c.domain : '.${c.domain}',
            path: c.path,
          ),
  ];

  /// 是否已持有 WebVPN 网关票据（wengine / vpn_ticket / webvpn 任一未过期 Cookie）。
  bool hasWebVPNTicket() {
    final now = DateTime.now();
    for (final entry in _store.entries) {
      for (final c in entry.value.values) {
        final n = c.name.toLowerCase();
        if ((c.domain == 'webvpn.neu.edu.cn') &&
            (n.contains('wengine') ||
                n.contains('vpn_ticket') ||
                n.contains('webvpn')) &&
            c.value.isNotEmpty &&
            (c.expires == null || now.isBefore(c.expires!))) {
          return true;
        }
      }
    }
    return false;
  }

  /// 丢弃现有 WebVPN 网关票据（票据可能与浏览器 UA 绑定被拒，重换后再试）。
  void removeWebVPNTickets() {
    for (final domain in _store.keys.toList()) {
      if (!domain.contains('webvpn.neu.edu.cn')) continue;
      final cookies = _store[domain];
      if (cookies == null) continue;
      for (final name in cookies.keys.toList()) {
        final n = cookies[name]!.name.toLowerCase();
        if (n.contains('wengine') ||
            n.contains('vpn_ticket') ||
            n.contains('webvpn')) {
          cookies.remove(name);
        }
      }
      if (cookies.isEmpty) _store.remove(domain);
    }
  }

  Map<String, Map<String, String>> cookieSnapshot() {
    final out = <String, Map<String, String>>{};
    for (final entry in _store.entries) {
      final m = <String, String>{};
      for (final c in entry.value.values) {
        if (!c.isExpired) m[c.name] = c.value;
      }
      if (m.isNotEmpty) {
        out[entry.key] = m;
        if (!entry.key.startsWith('.')) {
          out['.${entry.key}'] = Map.of(m);
        }
      }
    }
    return out;
  }
}

class PortalClient {
  PortalClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const passBase = 'https://pass.neu.edu.cn';
  static const portalBase = 'https://personal.neu.edu.cn/portal';

  final http.Client _http;
  final CookieJar _cookies = CookieJar();

  /// WebVPN 网关模式：校外门户 HTML 会被学校重定向进网关，开启后门户/教务请求改走网关。
  bool webvpnOn = false;
  AccessMode _accessMode = AccessMode.auto;
  AccessMode get accessMode => _accessMode;
  set accessMode(AccessMode value) {
    if (_accessMode == value) return;
    _accessMode = value;
    invalidateAccessRoute();
    webvpnOn = value == AccessMode.webvpn;
  }

  DateTime? _campusProbeAt;
  bool? _campusProbeResult;
  Future<bool>? _campusProbe;
  Future<void>? _accessPreparation;
  int _accessEpoch = 0;

  void invalidateAccessRoute() {
    _accessEpoch++;
    _campusProbeAt = null;
    _campusProbeResult = null;
    _campusProbe = null;
  }

  /// 是否已持有 WebVPN 网关票据（WebView 会话回收后可据此直接进入网关模式）。
  bool get hasWebVPNTicket => _cookies.hasWebVPNTicket();

  /// 是否持有 CAS 会话（CASTGC）。
  bool get hasCasSession => _cookies.hasCookie(
    Uri.parse('https://pass.neu.edu.cn/tpass/login'),
    'CASTGC',
  );

  @visibleForTesting
  CookieJar get cookies => _cookies;

  bool get isLoggedIn => _cookies.hasCookie(Uri.parse(portalBase), 'SESS_ID');

  List<({String name, String value, String domain, String path})>
  browserCookies() => _cookies.browserCookies();

  String? get userAgent => _userAgentOverride;

  List<Map<String, dynamic>> sessionCookies() => _cookies.sessionCookies();
  void clearSessionCookies() => _cookies.clear();
  void restoreSessionCookies(List<Map<String, dynamic>> cookies) =>
      _cookies.restoreSessionCookies(cookies);

  /// 供 WebView 注入的会话快照：host → {name: value}。
  Map<String, Map<String, String>> cookieSnapshot() => _cookies.cookieSnapshot();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Mobile Safari/537.36';

  /// 网页登录后覆盖为 WebView 的真实 UA：网关/WAF 会校验 UA 与会话一致性。
  String? _userAgentOverride;

  /// 网页登录完成后由 WebView 回传真实 UA。
  void setUserAgent(String ua) {
    if (ua.trim().isNotEmpty) _userAgentOverride = ua.trim();
  }

  Map<String, String> _headers(Uri uri, {bool xhr = false}) => {
        'User-Agent': _userAgentOverride ?? _ua,
        'Accept': 'application/json, text/html, */*',
        if (xhr) 'X-Requested-With': 'XMLHttpRequest',
        if (_cookies.headerFor(uri) != null) 'Cookie': _cookies.headerFor(uri)!,
      };

  /// Uses the same redirect/cookie/UA transport for platform readers.
  Future<({String text, Uri url})> readDocument(String url, {
    String method = 'GET', String? body, String? contentType, String? referer,
  }) async {
    final uri = Uri.parse(url);
    final request = http.Request(method, uri)..headers.addAll(_headers(uri));
    if (contentType != null) request.headers['Content-Type'] = contentType;
    if (body != null) request.body = body;
    if (referer != null) request.headers['Referer'] = referer;
    final response = await _send(request);
    final text = await _respText(response).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PortalException('平台返回 HTTP ${response.statusCode}');
    }
    return (text: text, url: response.request?.url ?? uri);
  }

  /// 手动跟随重定向，吸收每一跳的 Set-Cookie。
  Future<http.StreamedResponse> _send(
    http.BaseRequest req, {
    int maxHops = 10,
  }) async {
    for (var hop = 0; hop < maxHops; hop++) {
      req.followRedirects = false;
      final resp = await _http.send(req).timeout(const Duration(seconds: 10));
      _cookies.absorb(req.url, resp);
      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
        final next = Uri.parse(maybeWrap(req.url.resolve(loc).toString()));
        await resp.stream.drain<void>();
        final isGet = resp.statusCode == 301 ||
            resp.statusCode == 302 ||
            resp.statusCode == 303;
        final redirectHeaders = _headers(next);
        if (next.origin == req.url.origin) {
          for (final name in ['referer', 'origin']) {
            final value = req.headers[name];
            if (value != null) redirectHeaders[name] = value;
          }
        }
        if (!isGet && req.headers['content-type'] != null) {
          redirectHeaders['content-type'] = req.headers['content-type']!;
        }
        if (isGet && req is http.Request) {
          req = http.Request('GET', next)
            ..headers.addAll(redirectHeaders);
        } else if (req is http.Request) {
          req = http.Request(req.method, next)
            ..headers.addAll(redirectHeaders)
            ..bodyBytes = req.bodyBytes;
        } else {
          throw PortalException('无法跟随重定向：$loc');
        }
        continue;
      }
      return resp;
    }
    throw PortalException('重定向次数过多');
  }

  /// CAS 统一身份认证登录。成功返回用户信息，失败抛 PortalException。
  Future<PortalUser> login(String username, String password) async {
    _cookies.clear();
    final cleanUsername = username.replaceAll(RegExp(r'\s+'), '').trim();
    final cleanPassword = password;
    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      throw PortalException('学号/工号或密码不能为空');
    }
    await prepareAccess();
    final loginUri = Uri.parse(kNeuCasLoginUrl);

    // 1. 取登录页，解析 lt / execution
    final pageResp = await _send(http.Request('GET', loginUri)
      ..headers.addAll(_headers(loginUri)));
    final page = await _respText(pageResp);
    final lt = RegExp(r'name="lt"\s+value="([^"]+)"').firstMatch(page)?.group(1);
    final execution =
        RegExp(r'name="execution"\s+value="([^"]+)"').firstMatch(page)?.group(1);
    if (lt == null || execution == null) {
      throw PortalException('统一身份认证页加载失败，请检查网络或校园 VPN 后重试');
    }

    // 2. RSA 加密并提交
    final form = {
      'rsa': CasCrypto.encrypt(cleanUsername + cleanPassword),
      'ul': '${cleanUsername.length}',
      'pl': '${cleanPassword.length}',
      'lt': lt,
      'execution': execution,
      '_eventId': 'submit',
    };
    final postReq = http.Request('POST', loginUri)
      ..headers.addAll(_headers(loginUri))
      ..headers['Content-Type'] =
          'application/x-www-form-urlencoded; charset=UTF-8'
      ..body = form.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
    final postResp = await _send(postReq);
    final finalUrl = postResp.request?.url ?? loginUri;
    final postHtml = await _respText(postResp);

    // 3. 校验认证结果
    // 若最终停留/重定向在 CAS 登录页，说明认证未通过
    if (finalUrl.host.contains('pass.neu.edu.cn') ||
        finalUrl.path.contains('/tpass/login')) {
      // 新设备二次认证（图形码 + 短信，login_second.js 流程）
      if (postHtml.contains('second_auth_form') ||
          postHtml.contains('当前设备需进行身份验证')) {
        _secondAuthExecution = RegExp(r'name="execution"\s+value="([^"]+)"')
                .firstMatch(postHtml)
                ?.group(1) ??
            'e1s2';
        throw SecondAuthRequired('需要完成短信二次认证');
      }
      final m = RegExp(
        r'<(?:span|div|p)[^>]*id="(?:errormsg|msg|msg_i18n)"[^>]*>([\s\S]*?)<\/(?:span|div|p)>',
        caseSensitive: false,
      ).firstMatch(postHtml);
      final rawMsg = m?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (rawMsg != null && rawMsg.isNotEmpty && !rawMsg.contains('null')) {
        if (rawMsg.contains('账号不存在')) {
          throw PortalException(
              '账号不存在：若当前使用 5G/4G 移动网络或在校外，学校统一认证会拦截公网直连鉴权（返回账号不存在）。请切换至校园网 WiFi，或先连接校园 WebVPN。');
        }
        throw PortalException(rawMsg);
      }
      throw PortalException('账号或密码错误');
    }

    // 校外门户登录成功后会被学校重定向进 WebVPN 网关（网关无票据时 403
    // 显示「仅用于我校师生在校外登录」）：此时 CASTGC 已到手，
    // 换网关票据后改经网关读取门户，不要停在网关拦截页。
    if (finalUrl.host.contains('webvpn.neu.edu.cn')) {
      if (!await ensureWebVPN()) {
        throw PortalException('校外需经 WebVPN 访问门户，网关登录失败：请稍后重试，或连接校园网后直接登录');
      }
      return fetchUserInfo();
    }

    // 尝试直接从重定向抵达的门户首页解析用户信息
    if (finalUrl.toString().startsWith(portalBase)) {
      final user = _extractUserFromHtml(postHtml);
      if (user != null) return user;
    }

    // 若未能直接获取（例如重定向停在中间页），请求门户首页
    return fetchUserInfo();
  }

  /// 从 HTML 中提取 window.userInfoDSL。
  static PortalUser? extractUserFromHtml(String html) =>
      _extractUserFromHtml(html);

  static PortalUser? _extractUserFromHtml(String html) {
    final idx = html.indexOf('userInfoDSL');
    if (idx < 0) return null;
    final eqIdx = html.indexOf('=', idx);
    if (eqIdx < 0) return null;
    final startBrace = html.indexOf('{', eqIdx);
    if (startBrace < 0) return null;

    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = startBrace; i < html.length; i++) {
      final ch = html[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (ch == '{') {
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) {
            final jsonStr = html.substring(startBrace, i + 1);
            try {
              final decoded = jsonDecode(jsonStr);
              if (decoded is Map<String, dynamic>) {
                final user = PortalUser.fromInfoJson(decoded);
                return user.hasProfile ? user : null;
              }
            } catch (_) {}
            break;
          }
        }
      }
    }
    return null;
  }

  /// 从门户首页 HTML 中解析 window.userInfoDSL。
  /// 恢复已有会话时只验证一次；网络/WAF 故障不销毁仍可用于浏览器的票据。
  Future<PortalUser?> validateSavedSession() async {
    await prepareAccess();
    final uri = Uri.parse(maybeWrap(portalBase));
    final resp = await _send(
      http.Request('GET', uri)..headers.addAll(_headers(uri)),
    );
    final html = await _respText(resp);
    final landed = resp.request?.url;
    if ((landed?.host == 'pass.neu.edu.cn') ||
        RegExp(
          r'<input\b[^>]*type\s*=\s*["\x27]?password',
          caseSensitive: false,
        ).hasMatch(html)) {
      throw PortalException('登录会话已过期，请重新登录', sessionExpired: true);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PortalException('门户暂时不可用（${resp.statusCode}）');
    }
    return _extractUserFromHtml(html);
  }

  Future<PortalUser> fetchUserInfo() async {
    await prepareAccess();
    // 网关票据失效时重换，保留校内和手动直连的线路选择。
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0 && !webvpnOn) break;
      if (attempt == 2) {
        if (!hasCasSession) break;
        _cookies.removeWebVPNTickets();
      }
      if (attempt >= 1 && !await ensureWebVPN()) {
        throw PortalException('统一身份认证会话已失效，请重新登录');
      }
      final target = maybeWrap(portalBase);
      final resp = await _send(
        http.Request('GET', Uri.parse(target))
          ..headers.addAll(_headers(Uri.parse(target))),
      );
      final html = await _respText(resp);
      if (!_isPortalSessionFailure(resp, html)) {
        final user = _extractUserFromHtml(html);
        if (user != null) return user;
      }
    }
    throw PortalException('统一身份认证会话已失效，请重新登录');
  }

  /// 直连门户是否失败：落在 CAS 登录页 / 网关拦截页 / 网关域。
  static bool _isPortalSessionFailure(http.StreamedResponse resp, String html) {
    final url = resp.request?.url;
    final onPass = url != null &&
        (url.host.contains('pass.neu.edu.cn') ||
            url.path.contains('/tpass/login'));
    final onWebVPN = url != null && url.host.contains('webvpn.neu.edu.cn');
    final gate = onWebVPN &&
        (resp.statusCode == 403 || html.contains('仅用于我校师生在校外登录'));
    return onPass || gate || html.contains('当前设备需进行身份验证');
  }

  // ── 校园网 / WebVPN ────────────────────────────────────

  /// 并行探测校内服务，排除网关重定向、拦截页和 Wi-Fi 认证页。
  /// 短时缓存由回到前台、手动刷新和打开服务时主动失效。
  Future<bool> isCampusNet() async {
    final now = DateTime.now();
    final cached = _campusProbeResult;
    if (_campusProbeAt != null &&
        cached != null &&
        now.difference(_campusProbeAt!) < const Duration(seconds: 30)) {
      return cached;
    }
    if (_campusProbe != null) return _campusProbe!;
    final probe = Future.wait([
      _quickReachable('http://ecard.neu.edu.cn/'),
      _quickReachable('https://jwxt.neu.edu.cn/'),
    ]).then((results) => results.any((value) => value));
    _campusProbe = probe;
    final result = await probe;
    if (identical(_campusProbe, probe)) {
      _campusProbeAt = now;
      _campusProbeResult = result;
      _campusProbe = null;
    }
    return result;
  }

  Future<bool> _quickReachable(String url) async {
    try {
      final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
      final resp = await _http.send(req).timeout(const Duration(seconds: 3));
      final html = await _respText(resp).timeout(const Duration(seconds: 3));
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        final location = resp.headers['location'];
        if (location == null) return false;
        final next = req.url.resolve(location);
        if (WebVPN.isWrapped(next.toString()) ||
            WebVPN.isWrapped(next.queryParameters['service'] ?? '')) {
          return false;
        }
        return next.host == req.url.host ||
            (next.scheme == 'https' && next.host == 'pass.neu.edu.cn');
      }
      if (resp.statusCode < 200 ||
          resp.statusCode >= 300 ||
          html.contains('仅用于我校师生在校外登录')) {
        return false;
      }
      return RegExp(
        r'教务|强智|一卡通|校园卡|jwapp|selflogin|selfsearch',
        caseSensitive: false,
      ).hasMatch(html);
    } catch (_) {
      return false;
    }
  }

  /// 用公网一号通的 CASTGC 给 WebVPN 网关换票（必须走公网 pass，不能先开网关首页）。
  Future<bool> ensureWebVPN() async {
    if (accessMode == AccessMode.direct ||
        (accessMode == AccessMode.auto && _campusProbeResult == true)) {
      return false;
    }
    if (_cookies.hasWebVPNTicket()) {
      webvpnOn = true;
      return true;
    }
    final loginUrl =
        'https://pass.neu.edu.cn/tpass/login?service=${Uri.encodeComponent(WebVPN.casService)}';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await _send(http.Request('GET', Uri.parse(loginUrl))
          ..headers.addAll(_headers(Uri.parse(loginUrl))));
        await resp.stream.drain<void>();
        if (_cookies.hasWebVPNTicket()) {
          webvpnOn =
              accessMode != AccessMode.direct &&
              !(accessMode == AccessMode.auto && _campusProbeResult == true);
          return true;
        }
      } catch (_) {}
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  /// 统一登录、接口和浏览器线路，同一轮并行请求共用探测及换票。
  Future<void> prepareAccess() {
    return _accessPreparation ??= _prepareAccess().whenComplete(() {
      _accessPreparation = null;
    });
  }

  Future<void> _prepareAccess() async {
    final epoch = _accessEpoch;
    final campus = accessMode == AccessMode.auto ? await isCampusNet() : false;
    if (epoch != _accessEpoch) return _prepareAccess();
    webvpnOn = switch (accessMode) {
      AccessMode.auto => !campus,
      AccessMode.direct => false,
      AccessMode.webvpn => true,
    };
    if (webvpnOn && (hasCasSession || hasWebVPNTicket)) {
      await ensureWebVPN();
    }
  }

  String maybeWrap(String url) {
    final direct = WebVPN.unwrap(url);
    return webvpnOn && WebVPN.supports(direct) ? WebVPN.wrap(direct) : direct;
  }

  /// WebView 会话回收后：若已持有网关票据则直接进入网关模式。
  void adoptGatewayTicket() {
    if (accessMode != AccessMode.direct &&
        _campusProbeResult != true &&
        _cookies.hasWebVPNTicket()) {
      webvpnOn = true;
    }
  }

  // ── 新设备二次认证（图形码 + 短信，login_second.js 流程）──────

  /// 二次认证挑战页的 execution（e1s2），登录成功后置空。
  String? _secondAuthExecution;

  bool get hasPendingSecondAuth => _secondAuthExecution != null;

  /// 吸收网页登录（WebView）会话 Cookie（含 CASTGC / SESS_ID / 网关票据）。
  void absorbWebCookies(
      List<({String name, String value, String domain, String path})> cookies) {
    for (final c in cookies) {
      if (c.name.isEmpty || c.value.isEmpty || c.domain.isEmpty) continue;
      var domain = c.domain.toLowerCase();
      if (domain.startsWith('.')) domain = domain.substring(1);
      final uri = Uri.parse('https://$domain/');
      // A WebViewCookie has no security/expiry attributes. Keep richer metadata
      // already learned from HTTP/native storage when the value is unchanged.
      final existing = _cookies.sessionCookies().where((r) =>
          r['name'] == c.name && r['domain'] == domain && r['path'] == c.path);
      if (existing.any((r) => r['value'] == c.value)) continue;
      _cookies.absorbRaw(uri, '${c.name}=${c.value}; Domain=$domain; Path=${c.path}',
          metadataKnown: false);
    }
  }

  /// 拉取二次认证图形码（与登录共用 JSESSIONID 会话）。
  Future<Uint8List> fetchSecondAuthCaptcha() async {
    if (_secondAuthExecution == null) {
      throw PortalException('当前没有待验证的登录，请先登录');
    }
    final url = Uri.parse(
        'https://pass.neu.edu.cn/tpass/code?_=${DateTime.now().millisecondsSinceEpoch}');
    final resp = await _send(
        http.Request('GET', url)..headers.addAll(_headers(url)));
    final bytes = await resp.stream.toBytes();
    if (resp.statusCode != 200 || bytes.isEmpty) {
      throw PortalException('图形码获取失败，请重试');
    }
    return Uint8List.fromList(bytes);
  }

  /// 提交图形码，请求下发短信验证码。
  Future<void> requestSecondAuthSMS(String graphicCode) async {
    if (_secondAuthExecution == null) {
      throw PortalException('当前没有待验证的登录，请先登录');
    }
    final url = Uri.parse('https://pass.neu.edu.cn/tpass/secondAuthCode');
    final resp = await _send(http.Request('POST', url)
      ..headers.addAll(_headers(url))
      ..headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'
      ..body = 'code=${Uri.encodeComponent(graphicCode)}&method=mobile');
    final text = await _respText(resp);
    final lower = text.toLowerCase();
    if (resp.statusCode != 200 ||
        lower.contains('false') ||
        text.contains('验证码错误') ||
        text.contains('失败')) {
      throw PortalException('短信发送失败：请检查图形码是否正确后重试');
    }
  }

  /// 提交短信验证码完成二次认证并继续登录。
  Future<PortalUser> submitSecondAuth(String smsCode) async {
    final execution = _secondAuthExecution;
    if (execution == null) {
      throw PortalException('当前没有待验证的登录，请先登录');
    }
    final postResp = await _send(http.Request('POST', Uri.parse(kNeuCasLoginUrl))
      ..headers.addAll(_headers(Uri.parse(kNeuCasLoginUrl)))
      ..headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'
      ..body = {
        'execution': execution,
        'RelayState': execution,
        '_eventId': 'submit',
        'scendAuthCode': smsCode,
      }.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&'));
    final finalUrl = postResp.request?.url ?? Uri.parse(kNeuCasLoginUrl);
    final html = await _respText(postResp);
    if (finalUrl.host.contains('pass.neu.edu.cn') ||
        finalUrl.path.contains('/tpass/login')) {
      if (html.contains('second_auth_form') ||
          html.contains('当前设备需进行身份验证')) {
        _secondAuthExecution = RegExp(r'name="execution"\s+value="([^"]+)"')
                .firstMatch(html)
                ?.group(1) ??
            execution;
        throw PortalException('短信验证码不正确，请重新输入');
      }
      final m = RegExp(
        r'<(?:span|div|p)[^>]*id="(?:errormsg|msg|msg_i18n)"[^>]*>([\s\S]*?)<\/(?:span|div|p)>',
        caseSensitive: false,
      ).firstMatch(html);
      final rawMsg = m?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (rawMsg != null && rawMsg.isNotEmpty && !rawMsg.contains('null')) {
        throw PortalException(rawMsg);
      }
      throw PortalException('二次认证失败，请重新登录');
    }
    _secondAuthExecution = null;
    // 校外完成二次认证后同样可能被门户重定向进 WebVPN 网关
    if (finalUrl.host.contains('webvpn.neu.edu.cn')) {
      if (!await ensureWebVPN()) {
        throw PortalException('校外需经 WebVPN 访问门户，网关登录失败：请稍后重试，或连接校园网后直接登录');
      }
      return fetchUserInfo();
    }
    if (finalUrl.toString().startsWith(portalBase)) {
      final user = _extractUserFromHtml(html);
      if (user != null) return user;
    }
    return fetchUserInfo();
  }

  Future<Map<String, dynamic>> _api(String path,
      {Map<String, Object?>? query}) async {
    await prepareAccess();
    // 校外（网关模式）时门户 JSON 接口也必须经网关
    final uri = Uri.parse(maybeWrap('$portalBase/$path'))
        .replace(queryParameters: query);
    final resp = await _send(http.Request('GET', uri)
      ..headers.addAll(_headers(uri, xhr: true)));
    final finalUrl = resp.request?.url ?? uri;
    if (finalUrl.host.contains('pass.neu.edu.cn') ||
        finalUrl.path.contains('/tpass/login')) {
      throw PortalException('统一身份认证会话已失效，请重新登录');
    }
    final text = await _respText(resp);
    if (text.isEmpty) throw PortalException('接口返回为空');
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) throw PortalException('接口返回格式异常');
    final code = j['e'];
    if (code is int && code != 0) {
      throw PortalException('${j['m'] ?? '接口错误'}（代码 $code）');
    }
    return (j['d'] ?? {}) as Map<String, dynamic>;
  }

  /// 某一周（周日起 7 天）的课表/考试/活动事件。weekStart 传该周任意一天即可。
  Future<List<CourseOccurrence>> fetchWeek(DateTime anyDayInWeek) async {
    final start =
        DateTime(anyDayInWeek.year, anyDayInWeek.month, anyDayInWeek.day)
            .subtract(Duration(days: anyDayInWeek.weekday % 7)); // 回到周日
    final end = start.add(const Duration(days: 7)).millisecondsSinceEpoch - 1000;
    final d = await _api('schedule/frontend/default/week-list', query: {
      'calendar_id': '0',
      'classify[]': ['1', '2', '3', '4', '5', '6'],
      'start': '${start.millisecondsSinceEpoch}',
      'end': '$end',
    });
    final data = d['data'] as Map<String, dynamic>;
    final day = data['day'];
    final out = <CourseOccurrence>[];
    if (day is Map<String, dynamic>) {
      for (final entry in day.entries) {
        final date = DateTime.tryParse(entry.key);
        if (date == null) continue;
        final slots = entry.value;
        final List slotList =
            slots is List ? slots : (slots is Map ? slots.values.toList() : []);
        for (final slot in slotList) {
          final Map periods;
          if (slot is Map && slot.values.any((v) => v is Map)) {
            periods = slot;
          } else if (slot is List) {
            periods = {for (var i = 0; i < slot.length; i++) '$i': slot[i]};
          } else {
            continue;
          }
          for (final ev in periods.values) {
            if (ev is! Map || '${ev['con'] ?? ''}'.isEmpty) continue;
            final s = DateTime.tryParse('${ev['start_time'] ?? ''}');
            final e = DateTime.tryParse('${ev['end'] ?? ''}');
            if (s == null || e == null) continue;
            out.add(
              CourseOccurrence(
                date,
                CourseSlot(
                  weekday: date.weekday,
                  startMinutes: s.hour * 60 + s.minute,
                  endMinutes: e.hour * 60 + e.minute,
                  name: '${ev['con']}',
                  room: '${ev['location'] ?? ''}'.trim().isEmpty
                      ? '待定'
                      : '${ev['location']}'.trim(),
                ),
              ),
            );
          }
        }
      }
    }
    return out;
  }

  Future<List<PortalApp>> fetchApps() async {
    final d = await _api('appmarket/frontend/default/getApp', query: {
      'limit': '999',
      'type': 'all',
      'cate_id': '',
    });
    final list = d['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((a) => PortalApp(
              name: '${a['name'] ?? ''}',
              appId: '${a['id'] ?? ''}',
              url: '${a['url'] ?? a['mobile_url'] ?? ''}',
              mobileUrl: '${a['mobile_url'] ?? ''}',
              iconUrl: '${a['icon'] ?? ''}',
              desc: '${a['dsc'] ?? ''}',
              category: '${a['category_name'] ?? ''}'.split(',').first.trim(),
              visits: int.tryParse('${a['fwl'] ?? 0}') ?? 0,
            ))
        .where((a) => a.name.isNotEmpty)
        .toList();
  }

  Future<List<NewsItem>> fetchNews({int pageSize = 12}) async {
    final tabs = await _api('news/frontend/default/tabs',
        query: {'system': '', 'need_num': '1'});
    String cid = '1244bca0563f72ea134e4d78973c6911';
    String cname = '东大要闻';
    final tl = tabs['list'];
    if (tl is List && tl.isNotEmpty) {
      final first = tl.whereType<Map>().firstWhere(
            (t) => '${t['name']}' == '东大要闻',
            orElse: () => tl.first as Map,
          );
      cid = '${first['id']}';
      cname = '${first['name']}';
    }
    final d = await _api('news/frontend/default/news-list', query: {
      'system': '',
      'cid': cid,
      'need_all': '0',
      'page': '1',
      'pageSize': '$pageSize',
      'keyword': '',
      'year': '',
      'month': '',
      'publisher': '',
    });
    final list = d['list'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((n) {
      return NewsItem(
        id: '${n['id'] ?? n['contentid'] ?? ''}',
        title: '${n['title'] ?? ''}',
        date: '${n['publish_time'] ?? ''}'.split(' ').first,
        category: cname,
        url: '${n['url'] ?? ''}',
        picUrl: '${n['picurl'] ?? ''}',
      );
    }).where((n) => n.title.isNotEmpty).toList();
  }

  Future<List<TodoItem>> fetchTodos() async {
    try {
      final d = await _api('personal/frontend/task/apply',
          query: {'type': 'all', 'page': '1', 'pageSize': '10'});
      final list = d['list'];
      if (list is! List) return const [];
      return list.whereType<Map>().map((t) => TodoItem(
            title: '${t['third_app_name'] ?? ''}',
            instance: '${t['third_inst_name'] ?? ''}',
            node: (t['node_name'] is List && (t['node_name'] as List).isNotEmpty)
                ? '${(t['node_name'] as List).last}'
                : '处理中',
            percent: int.tryParse('${t['percent'] ?? 0}') ?? 0,
            time: '${t['inst_created'] ?? ''}'.split('.').first,
            url: '${t['form_mobile_url_view'] ?? t['form_url_view'] ?? ''}',
          )).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<DataCard>> fetchDataCards() async {
    try {
      final d = await _api('personal/frontend/data/items',
          query: {'type': 'personal_data'});
      final list = (d['data'] as List?) ?? const [];
      final out = <DataCard>[];
      for (final it in list.whereType<Map>()) {
        final name = '${it['name'] ?? ''}';
        if (name.isEmpty) continue;
        var value = '—';
        // 值在详情接口里，容错解析
        try {
          final id = '${it['id'] ?? ''}';
          if (id.isNotEmpty) {
            final det = await _api('personal/frontend/data/detail',
                query: {'id': id});
            final inner = det['data'];
            for (final cand in [
              if (inner is Map) inner['value'],
              if (inner is Map) inner['data'],
              if (inner is Map) inner['text'],
              inner,
            ]) {
              if (cand == null) continue;
              final s = '$cand';
              if (s.isNotEmpty && s.length <= 12) {
                value = s;
                break;
              }
            }
          }
        } catch (_) {}
        out.add(DataCard(name, value));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 门户智慧搜索热词。
  Future<List<String>> fetchHotSearch({int pageSize = 8}) async {
    final raw = await _jwxtLikeGet(
        'frontend/search/hot?pageSize=$pageSize');
    final j = jsonDecode(raw);
    if (j['e'] != 0) return const [];
    final list = ((j['d'] ?? {})['list'] ?? []) as List;
    return list.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }

  Future<String> _jwxtLikeGet(String ep) async {
    await prepareAccess();
    final u = maybeWrap('$portalBase/$ep');
    final req = http.Request('GET', Uri.parse(u))
      ..headers.addAll(_headers(Uri.parse(u)));
    final resp = await _send(req);
    return _respText(resp);
  }

  // ── 教务系统（强智 jwapp）真实成绩 ────────────────────
  static const _jwxtBase = 'https://jwxt.neu.edu.cn';

  /// 跟随重定向 SSO 进入教务系统（CASTGC 会被 CAS 识别，建立 jwapp 会话）。
  /// 校外自动先经 WebVPN：探测 + 换网关票据，请求与重定向目标都改走网关。
  Future<void> _jwxtSso() async {
    await prepareAccess();
    var u = maybeWrap('$_jwxtBase/');
    for (var i = 0; i < 10; i++) {
      final req = http.Request('GET', Uri.parse(u))
        ..headers.addAll(_headers(Uri.parse(u)));
      final resp = await _send(req);
      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
        var next = Uri.parse(u).resolve(loc).toString();
        if (webvpnOn && WebVPN.isIntranet(next) && !WebVPN.isWrapped(next)) {
          next = WebVPN.wrap(next);
        }
        u = next;
        continue;
      }
      return;
    }
  }

  Future<String> _jwxtGet(String path) async {
    final u = maybeWrap('$_jwxtBase/$path');
    final req = http.Request('GET', Uri.parse(u))
      ..headers.addAll(_headers(Uri.parse(u)));
    final resp = await _send(req);
    return _respText(resp);
  }

  /// 全部学期的真实成绩（成绩可能为数字或五级制文本，如「良」）。
  Future<List<GradeSemester>> fetchJwxtGrades() async =>
      (await fetchGradeReport()).semesters;

  Future<GradeReport> fetchGradeReport() async {
    await _jwxtSso();
    final calendar = jsonDecode(await _jwxtGet(
        'jwapp/sys/homeapp/api/home/student/schoolCalendars.do'));
    validateAcademic(calendar);
    final out = <GradeSemester>[];
    final failed = <String>[];
    for (final term in academicRecords(calendar)) {
      final code = '${term['itemCode'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      try {
        final raw = await _jwxtGet(
            'jwapp/sys/homeapp/api/home/student/scores.do?termCode=${Uri.encodeComponent(code)}');
        out.add(parseGradeSemester(jsonDecode(raw), code,
            '${term['itemName'] ?? code}', ['true', '1'].contains('${term['selected']}')));
      } catch (_) { failed.add(code); }
    }
    if (out.isEmpty) throw PortalException('本次未读取到成绩，请重试或在教务网页同步');
    return GradeReport(out, failedTerms: failed);
  }

  static Future<String> _respText(http.StreamedResponse resp) async {
    final bytes = await resp.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  void dispose() => _http.close();
}
