/// 一号通门户客户端：CAS 登录 + 各业务接口。
/// 手动重定向 + RFC 规范 Cookie 罐，保证 CASTGC / SESS_ID 全程正确跨域传递。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cas_crypto.dart';
import 'models.dart';
import 'webvpn.dart';

class PortalException implements Exception {
  final String message;
  PortalException(this.message);
  @override
  String toString() => message;
}

class _CookieEntry {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;

  _CookieEntry({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expires,
  });

  bool get isExpired {
    if (expires != null && DateTime.now().isAfter(expires!)) return true;
    return false;
  }
}

class CookieJar {
  /// domain/host -> (cookie name -> _CookieEntry)
  final Map<String, Map<String, _CookieEntry>> _store = {};

  static List<String> splitSetCookie(String raw) {
    final result = <String>[];
    var start = 0;
    var inExpires = false;
    for (var i = 0; i < raw.length; i++) {
      if (i >= 8 && raw.substring(i - 8, i).toLowerCase() == 'expires=') {
        inExpires = true;
      }
      if (raw[i] == ';') {
        inExpires = false;
      }
      if (raw[i] == ',') {
        if (inExpires) continue;
        final part = raw.substring(start, i).trim();
        if (part.isNotEmpty) result.add(part);
        start = i + 1;
      }
    }
    final last = raw.substring(start).trim();
    if (last.isNotEmpty) result.add(last);
    return result;
  }

  void absorb(Uri uri, http.StreamedResponse resp) {
    absorbRaw(uri, resp.headers['set-cookie']);
  }

  void absorbRaw(Uri uri, String? sc) {
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
      DateTime? expires;
      var expired = value.isEmpty;

      for (var i = 1; i < parts.length; i++) {
        final attr = parts[i].trim();
        final attrEq = attr.indexOf('=');
        final attrName =
            (attrEq > 0 ? attr.substring(0, attrEq) : attr).trim().toLowerCase();
        final attrVal = attrEq > 0 ? attr.substring(attrEq + 1).trim() : '';

        if (attrName == 'domain' && attrVal.isNotEmpty) {
          domain = attrVal.toLowerCase();
          if (domain.startsWith('.')) domain = domain.substring(1);
        } else if (attrName == 'path' && attrVal.isNotEmpty) {
          path = attrVal;
        } else if (attrName == 'max-age') {
          final sec = int.tryParse(attrVal);
          if (sec != null) {
            if (sec <= 0) {
              expired = true;
            } else {
              expires = DateTime.now().add(Duration(seconds: sec));
            }
          }
        }
      }

      final domainStore = _store.putIfAbsent(domain, () => {});
      if (expired) {
        domainStore.remove(name);
      } else {
        domainStore[name] = _CookieEntry(
          name: name,
          value: value,
          domain: domain,
          path: path,
          expires: expires,
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

  String? headerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final pairs = <String>[];

    for (final entry in _store.entries) {
      if (_matchesDomain(host, entry.key)) {
        for (final cookie in entry.value.values) {
          if (!cookie.isExpired &&
              (cookie.path == '/' || path.startsWith(cookie.path))) {
            pairs.add('${cookie.name}=${cookie.value}');
          }
        }
      }
    }
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  bool hasCookie(Uri uri, String name) {
    final host = uri.host.toLowerCase();
    for (final entry in _store.entries) {
      if (_matchesDomain(host, entry.key)) {
        final c = entry.value[name];
        if (c != null && !c.isExpired && c.value.isNotEmpty) return true;
      }
    }
    return false;
  }

  /// 是否已持有 WebVPN 网关票据（wengine / vpn_ticket / webvpn 任一未过期 Cookie）。
  bool hasWebVPNTicket() {
    final now = DateTime.now();
    for (final entry in _store.entries) {
      for (final c in entry.value.values) {
        final n = c.name.toLowerCase();
        if ((n.contains('wengine') || n.contains('vpn_ticket') || n.contains('webvpn')) &&
            c.value.isNotEmpty &&
            (c.expires == null || now.isBefore(c.expires!))) {
          return true;
        }
      }
    }
    return false;
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
  static const passBase = 'https://pass.neu.edu.cn';
  static const portalBase = 'https://personal.neu.edu.cn/portal';

  final http.Client _http = http.Client();
  final CookieJar _cookies = CookieJar();

  /// WebVPN 网关模式：校外门户 HTML 会被学校重定向进网关，开启后门户/教务请求改走网关。
  bool webvpnOn = false;
  DateTime? _campusProbeAt;
  bool? _campusProbeResult;

  @visibleForTesting
  CookieJar get cookies => _cookies;

  bool get isLoggedIn => _cookies.hasCookie(Uri.parse(portalBase), 'SESS_ID');

  /// 供 WebView 注入的会话快照：host → {name: value}。
  Map<String, Map<String, String>> cookieSnapshot() => _cookies.cookieSnapshot();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Mobile Safari/537.36';

  Map<String, String> _headers(Uri uri, {bool xhr = false}) => {
        'User-Agent': _ua,
        'Accept': 'application/json, text/html, */*',
        if (xhr) 'X-Requested-With': 'XMLHttpRequest',
        if (_cookies.headerFor(uri) != null) 'Cookie': _cookies.headerFor(uri)!,
      };

  /// 手动跟随重定向，吸收每一跳的 Set-Cookie。
  Future<http.StreamedResponse> _send(http.BaseRequest req,
      {int maxHops = 10}) async {
    for (var hop = 0; hop < maxHops; hop++) {
      req.followRedirects = false;
      final resp = await _http.send(req).timeout(const Duration(seconds: 10));
      _cookies.absorb(Uri.parse('${req.url.scheme}://${req.url.host}'), resp);
      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
        final next = Uri.parse(req.url.toString()).resolve(loc);
        final isGet = resp.statusCode == 301 ||
            resp.statusCode == 302 ||
            resp.statusCode == 303;
        if (isGet && req is http.Request) {
          req = http.Request('GET', next)
            ..headers.addAll(_headers(next));
        } else if (req is http.Request) {
          req = http.Request(req.method, next)
            ..headers.addAll(_headers(next))
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
      throw PortalException('账号或密码错误（如需二次短信验证，请先在网页端完成设备信任绑定）');
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
  @visibleForTesting
  static PortalUser? extractUserFromHtml(String html) => _extractUserFromHtml(html);

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
                return PortalUser.fromInfoJson(decoded);
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
  Future<PortalUser> fetchUserInfo() async {
    var target = maybeWrap(portalBase);
    var resp = await _send(http.Request('GET', Uri.parse(target))
      ..headers.addAll(_headers(Uri.parse(target))));
    var html = await _respText(resp);
    if (_isWebVPNBlockedPage(resp, html)) {
      webvpnOn = false;
      if (!await ensureWebVPN()) {
        throw PortalException('WebVPN 网关登录失败：请稍后重试，或连接校园网后直接登录');
      }
      target = maybeWrap(portalBase);
      resp = await _send(http.Request('GET', Uri.parse(target))
        ..headers.addAll(_headers(Uri.parse(target))));
      html = await _respText(resp);
    }
    final finalUrl = resp.request?.url ?? Uri.parse(target);
    if (finalUrl.host.contains('pass.neu.edu.cn') ||
        finalUrl.path.contains('/tpass/login')) {
      throw PortalException('统一身份认证会话已失效，请重新登录');
    }

    final user = _extractUserFromHtml(html);
    if (user != null) return user;

    throw PortalException('会话未能正常建立，请重新登录');
  }

  /// WebVPN 网关的拦截页（未携带网关会话时的 403 提示页）。
  static bool _isWebVPNBlockedPage(http.StreamedResponse resp, String html) {
    final url = resp.request?.url;
    if (url == null || !url.host.contains('webvpn.neu.edu.cn')) return false;
    return resp.statusCode == 403 || html.contains('仅用于我校师生在校外登录');
  }

  // ── 校园网 / WebVPN ────────────────────────────────────

  /// 是否校园网：ecard:80 或 jwxt:443 任一可达（结果缓存 10 分钟）。
  Future<bool> isCampusNet() async {
    final now = DateTime.now();
    final cached = _campusProbeResult;
    if (_campusProbeAt != null &&
        cached != null &&
        now.difference(_campusProbeAt!).inMinutes < 10) {
      return cached;
    }
    final ecard = await _quickReachable('http://ecard.neu.edu.cn/');
    final ok = ecard || await _quickReachable('https://jwxt.neu.edu.cn/');
    _campusProbeAt = now;
    _campusProbeResult = ok;
    if (ok) webvpnOn = false;
    return ok;
  }

  Future<bool> _quickReachable(String url) async {
    try {
      final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
      await _http.send(req).timeout(const Duration(seconds: 3));
      return true; // 任何 HTTP 响应都算可达
    } catch (_) {
      return false;
    }
  }

  /// 用公网一号通的 CASTGC 给 WebVPN 网关换票（必须走公网 pass，不能先开网关首页）。
  Future<bool> ensureWebVPN() async {
    if (webvpnOn && _cookies.hasWebVPNTicket()) return true;
    final loginUrl =
        'https://pass.neu.edu.cn/tpass/login?service=${Uri.encodeComponent(WebVPN.casService)}';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await _send(http.Request('GET', Uri.parse(loginUrl))
          ..headers.addAll(_headers(Uri.parse(loginUrl))));
        final landed = resp.request?.url.toString() ?? '';
        if (_cookies.hasWebVPNTicket() ||
            (landed.contains('webvpn.neu.edu.cn') &&
                !landed.contains('/tpass/login'))) {
          webvpnOn = true;
          return true;
        }
      } catch (_) {}
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  /// 校外准备：探测校园网，校外则种网关票据。
  Future<void> prepareAccess() async {
    if (await isCampusNet()) return;
    await ensureWebVPN();
  }

  String maybeWrap(String url) {
    if (!webvpnOn) return url;
    if (WebVPN.isIntranet(url)) return WebVPN.wrap(url);
    // 校外门户 HTML 会被学校重定向进网关，门户域的请求统一改走网关
    final lowered = url.toLowerCase();
    if (lowered.contains('personal.neu.edu.cn') ||
        lowered.contains('portal.neu.edu.cn')) {
      return WebVPN.wrap(url);
    }
    return url;
  }

  Future<Map<String, dynamic>> _api(String path,
      {Map<String, Object?>? query}) async {
    final uri = Uri.parse('$portalBase/$path')
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
            out.add(CourseOccurrence(
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
            ));
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
    final u = '$portalBase/$ep';
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
  Future<List<GradeSemester>> fetchJwxtGrades() async {
    await _jwxtSso();
    final calRaw = await _jwxtGet(
        'jwapp/sys/homeapp/api/home/student/schoolCalendars.do');
    final cal = jsonDecode(calRaw);
    if (cal['code'] != '0') throw PortalException('学期列表获取失败');
    final terms = ((cal['datas'] ?? []) as List).whereType<Map>().toList();
    final out = <GradeSemester>[];
    for (final t in terms) {
      final code = '${t['itemCode'] ?? ''}'.trim();
      final name = '${t['itemName'] ?? code}'.trim();
      if (code.isEmpty) continue;
      final raw = await _jwxtGet(
          'jwapp/sys/homeapp/api/home/student/scores.do?termCode=$code');
      final j = jsonDecode(raw);
      if (j['code'] != '0') continue;
      final list = ((j['datas'] ?? []) as List).whereType<Map>().toList();
      final courses = list.map((c) {
        final scoreRaw = '${c['score'] ?? ''}'.trim();
        final scoreNum = double.tryParse(scoreRaw);
        return GradeCourse(
          name: '${c['courseName'] ?? ''}',
          credit: double.tryParse('${c['credit'] ?? 0}') ?? 0,
          category: '${c['courseType'] ?? ''}',
          score: scoreNum,
          scoreRaw: scoreNum == null ? scoreRaw : '',
        );
      }).where((c) => c.name.isNotEmpty).toList();
      final selected = t['selected'] == true;
      out.add(GradeSemester(name,
          termCode: code, current: selected, courses: courses));
    }
    if (out.isEmpty) throw PortalException('未获取到成绩数据');
    return out;
  }

  static Future<String> _respText(http.StreamedResponse resp) async {
    final bytes = await resp.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  void dispose() => _http.close();
}
