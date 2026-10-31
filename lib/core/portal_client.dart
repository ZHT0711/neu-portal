/// 一号通门户客户端：CAS 登录 + 各业务接口。
/// 手动重定向 + Cookie 罐，保证 CASTGC / SESS_ID 全程正确传递。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cas_crypto.dart';
import 'models.dart';

class PortalException implements Exception {
  final String message;
  PortalException(this.message);
  @override
  String toString() => message;
}

class _CookieJar {
  final Map<String, Map<String, String>> _byHost = {};

  void absorb(Uri uri, http.StreamedResponse resp) {
    final sc = resp.headers['set-cookie'];
    if (sc == null || sc.isEmpty) return;
    final host = uri.host;
    final store = _byHost.putIfAbsent(host, () => {});
    for (final part in _splitSetCookie(sc)) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      var value = part.substring(i + 1).trim();
      final semi = value.indexOf(';');
      if (semi >= 0) value = value.substring(0, semi);
      if (value.isEmpty) {
        store.remove(name);
      } else {
        store[name] = value;
      }
    }
  }

  void clear() => _byHost.clear();

  String? headerFor(Uri uri) {
    final exact = _byHost[uri.host];
    final pairs = <String>[];
    if (exact != null) {
      exact.forEach((k, v) => pairs.add('$k=$v'));
    }
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  bool hasCookie(Uri uri, String name) =>
      _byHost[uri.host]?[name] != null;

  /// 处理 http 包把多个 Set-Cookie 拼在一起的情况。
  static Iterable<String> _splitSetCookie(String sc) sync* {
    final buf = StringBuffer();
    var inDate = false;
    for (var i = 0; i < sc.length; i++) {
      final ch = sc[i];
      if (ch == ',' && !inDate) {
        final s = buf.toString().trim();
        if (s.isNotEmpty) yield s;
        buf.clear();
        continue;
      }
      // Expires=Wed, 21 Oct ... 中逗号后跟空格+两位数字/字母即日期内部
      if (inDate && ch == ' ') {
        inDate = false;
      }
      if (ch == ';' && sc.startsWith(RegExp(r'expires=', caseSensitive: false), i + 1)) {
        inDate = true;
      }
      buf.write(ch);
    }
    final last = buf.toString().trim();
    if (last.isNotEmpty) yield last;
  }
}

class PortalClient {
  static const passBase = 'https://pass.neu.edu.cn';
  static const portalBase = 'https://personal.neu.edu.cn/portal';

  final http.Client _http = http.Client();
  final _CookieJar _cookies = _CookieJar();

  bool get isLoggedIn => _cookies.hasCookie(Uri.parse(portalBase), 'SESS_ID');

  /// 供 WebView 注入的会话快照：host → {name: value}。
  Map<String, Map<String, String>> cookieSnapshot() {
    final out = <String, Map<String, String>>{};
    _cookies._byHost.forEach((host, kv) {
      if (kv.isNotEmpty) out[host] = Map.of(kv);
    });
    return out;
  }

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
      final resp = await _http.send(req).timeout(const Duration(seconds: 20));
      _cookies.absorb(Uri.parse('${req.url.scheme}://${req.url.host}'), resp);
      // http 包的 headers 已按 host 记录；上面 absorb 用 req.url 更准确
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
    final loginUri = Uri.parse(kNeuCasLoginUrl);

    // 1. 取登录页，解析 lt / execution
    final pageResp = await _send(http.Request('GET', loginUri)
      ..headers.addAll(_headers(loginUri)));
    final page = await _respText(pageResp);
    final lt = RegExp(r'name="lt"\s+value="([^"]+)"').firstMatch(page)?.group(1);
    final execution =
        RegExp(r'name="execution"\s+value="([^"]+)"').firstMatch(page)?.group(1);
    if (lt == null || execution == null) {
      throw PortalException('登录页解析失败，请稍后重试');
    }

    // 2. RSA 加密并提交
    final form = {
      'rsa': CasCrypto.encrypt(username + password),
      'ul': '${username.length}',
      'pl': '${password.length}',
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

    // 3. 校验会话
    final sessUri = Uri.parse(portalBase);
    if (!_cookies.hasCookie(sessUri, 'SESS_ID')) {
      final body = await _respText(postResp);
      final m = RegExp(r'id="(?:msg|errorMsg)"[^>]*>([^<]+)<').firstMatch(body);
      throw PortalException(
          m?.group(1)?.trim() ?? '账号或密码错误（或需要二次验证）');
    }
    if (!finalUrl.toString().startsWith(portalBase)) {
      // 再跟一次到门户
      await _send(http.Request('GET', Uri.parse(portalBase))
        ..headers.addAll(_headers(sessUri)));
    }
    return fetchUserInfo();
  }

  /// 从门户首页 HTML 中解析 window.userInfoDSL。
  Future<PortalUser> fetchUserInfo() async {
    final uri = Uri.parse(portalBase);
    final resp = await _send(http.Request('GET', uri)
      ..headers.addAll(_headers(uri)));
    final html = await _respText(resp);
    final m = RegExp(r'window\.userInfoDSL\s*=\s*(\{.*?\})\s*<').firstMatch(html);
    if (m == null) throw PortalException('会话已失效，请重新登录');
    final j = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    return PortalUser.fromInfoJson(j);
  }

  Future<Map<String, dynamic>> _api(String path,
      {Map<String, Object?>? query}) async {
    final uri = Uri.parse('$portalBase/$path')
        .replace(queryParameters: query);
    final resp = await _send(http.Request('GET', uri)
      ..headers.addAll(_headers(uri, xhr: true)));
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
  Future<void> _jwxtSso() async {
    var u = '$_jwxtBase/';
    for (var i = 0; i < 10; i++) {
      final req = http.Request('GET', Uri.parse(u))
        ..headers.addAll(_headers(Uri.parse(u)));
      final resp = await _send(req);
      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
        u = Uri.parse(u).resolve(loc).toString();
        continue;
      }
      return;
    }
  }

  Future<String> _jwxtGet(String path) async {
    final u = '$_jwxtBase/$path';
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
