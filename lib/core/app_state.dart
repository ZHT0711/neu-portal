/// 全局应用状态：会话、数据、主题设置。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_data.dart';
import 'models.dart';
import 'web_cookies.dart';
import 'platform_style.dart';
import 'portal_client.dart';
import 'semester.dart';
import 'theme.dart';

enum SessionMode { live, demo }

/// iOS 液态玻璃底栏引擎模式（两全其美：原生质感 vs GPU 零发热极速）
enum LiquidTabBarMode {
  native,       // 原生液态玻璃 (UIKit 原生底栏，真实 iOS 设备生效)
  fluidCapsule, // 极速流体悬浮胶囊 (GPU Metal 硬件加速，带滑动流体光斑)
  dockGlass,    // 全宽经典玻璃栏 (Cupertino 玻璃栏)
}

class AppState extends ChangeNotifier {
  AppState();

  @visibleForTesting
  AppState.withClient(this._client);

  PortalClient? _client;

  SessionMode mode = SessionMode.demo;
  PortalUser user = PortalUser.demo;
  bool liveAvailable = false; // 登录后实时数据是否全部就绪

  List<CourseSlot> scheduleTemplate = demoSchedule;
  List<PortalApp> apps = demoApps;
  List<NewsItem> news = demoNews;
  List<TodoItem> todos = demoTodos;
  List<DataCard> dataCards = demoDataCards;
  List<ServiceSection> services = demoServices;
  List<GradeSemester> semesters = demoSemesters;

  bool loading = false;
  String? lastError;

  /// 统一认证要求新设备短信二次认证（图形码已就绪状态由 secondAuthCaptcha 表示）。
  bool needsSecondAuth = false;
  Uint8List? secondAuthCaptcha;

  /// 用户添加的日程（考试、事务、提醒…），本地持久化。
  List<PlannerEvent> events = [];

  /// 门户智慧搜索热词（实时；离线为快照）。
  List<String> hotSearches = demoHotSearches;

  Future<void> addEvent(PlannerEvent e) async {
    events = [...events, e]..sort((a, b) {
        final c = a.dateIso.compareTo(b.dateIso);
        return c != 0 ? c : a.startMinutes.compareTo(b.startMinutes);
      });
    await _saveEvents();
    notifyListeners();
  }

  Future<void> removeEvent(String id) async {
    events = events.where((e) => e.id != id).toList();
    await _saveEvents();
    notifyListeners();
  }

  Future<void> _saveEvents() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kEvents, jsonEncode(events.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// 最近一次真实服务列表缓存：退出登录/离线时展示完整服务而非演示缩略表。
  Future<void> _saveAppsCache(List<PortalApp> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kAppsCache,
          jsonEncode(list
              .map((a) => {
                    'name': a.name,
                    'appId': a.appId,
                    'url': a.url,
                    'mobileUrl': a.mobileUrl,
                    'iconUrl': a.iconUrl,
                    'desc': a.desc,
                    'category': a.category,
                    'visits': a.visits,
                  })
              .toList()));
    } catch (_) {}
  }

  Future<List<PortalApp>> _loadAppsCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kAppsCache);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((j) => PortalApp(
                name: '${j['name'] ?? ''}',
                appId: '${j['appId'] ?? ''}',
                url: '${j['url'] ?? ''}',
                mobileUrl: '${j['mobileUrl'] ?? ''}',
                iconUrl: '${j['iconUrl'] ?? ''}',
                desc: '${j['desc'] ?? ''}',
                category: '${j['category'] ?? ''}',
                visits: int.tryParse('${j['visits'] ?? 0}') ?? 0,
              ))
          .where((a) => a.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 吸收 WebView 会话（单点登出/过期后页面内自愈用）。
  void absorbWebSession(
      List<({String name, String value, String domain, String path})> cookies) {
    _client?.absorbWebCookies(cookies);
  }

  // ── 外观设置（持久化）───────────────────────────────
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = NeuColors.seed;
  bool useDynamicColor = false;
  PlatformStylePreference platformStyle = PlatformStylePreference.auto;
  LiquidTabBarMode liquidTabBarMode = LiquidTabBarMode.native;

  static const _kMode = 'ui.themeMode';
  static const _kSeed = 'ui.seed';
  static const _kDyn = 'ui.dynamic';
  static const _kPlatform = 'ui.platform';
  static const _kGlassMode = 'ui.liquidTabBarMode';
  static const _kEvents = 'planner.events';
  static const _kSession = 'session.mode';
  static const _kAppsCache = 'cache.apps';
  static const _kWebUa = 'session.webUserAgent';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// 上次是否处于登录态（重启后自动续登用）。
  bool _persistedLive = false;
  bool _restoring = false;

  Future<void> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt(_kMode) ?? 0];
    useDynamicColor = p.getBool(_kDyn) ?? false;
    final s = p.getInt(_kSeed);
    if (s != null) seedColor = Color(s);
    final platIdx = p.getInt(_kPlatform);
    if (platIdx != null &&
        platIdx >= 0 &&
        platIdx < PlatformStylePreference.values.length) {
      platformStyle = PlatformStylePreference.values[platIdx];
    } else if (kIsWeb) {
      final q = Uri.base.queryParameters['platform'] ??
          Uri.base.queryParameters['style'];
      if (q == 'ios') {
        platformStyle = PlatformStylePreference.ios;
      } else if (q == 'android') {
        platformStyle = PlatformStylePreference.android;
      }
    }
    final glassModeIdx = p.getInt(_kGlassMode);
    if (glassModeIdx != null &&
        glassModeIdx >= 0 &&
        glassModeIdx < LiquidTabBarMode.values.length) {
      liquidTabBarMode = LiquidTabBarMode.values[glassModeIdx];
    }
    setPlatformPreference(platformStyle);
    _persistedLive = (p.getInt(_kSession) ?? 0) == 1;
    final cachedApps = await _loadAppsCache();
    if (cachedApps.isNotEmpty) apps = mergePortalApps([demoApps, cachedApps]);
    try {
      final raw = p.getString(_kEvents);
      if (raw != null && raw.isNotEmpty) {
        events = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((j) => PlannerEvent.fromJson(Map<String, dynamic>.from(j)))
            .toList();
      }
    } catch (_) {
      events = [];
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMode, m.index);
    notifyListeners();
  }

  Future<void> setPlatformStyle(PlatformStylePreference style) async {
    platformStyle = style;
    setPlatformPreference(style);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kPlatform, style.index);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setLiquidTabBarMode(LiquidTabBarMode mode) async {
    liquidTabBarMode = mode;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kGlassMode, mode.index);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setSeedColor(Color c) async {
    seedColor = c;
    useDynamicColor = false;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSeed, c.toARGB32());
    await p.setBool(_kDyn, false);
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool v) async {
    useDynamicColor = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDyn, v);
    notifyListeners();
  }

  // ── 登录 / 退出 / 免登录 ─────────────────────────────
  Future<void> login(String username, String password) async {
    loading = true;
    lastError = null;
    needsSecondAuth = false;
    notifyListeners();
    try {
      _client?.dispose();
      final c = PortalClient();
      _client = c;
      final u = await c.login(username, password);
      user = u;
      mode = SessionMode.live;
      _persistedLive = true;
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSession, 1);
      await _refreshLive();
    } on SecondAuthRequired {
      // 新设备二次认证：凭据先由登录页暂存，图形码 + 短信完成后回填
      needsSecondAuth = true;
      lastError = null;
      notifyListeners();
      rethrow;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 拉取二次认证图形码。
  Future<void> loadSecondAuthCaptcha() async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    secondAuthCaptcha = await c.fetchSecondAuthCaptcha();
    notifyListeners();
  }

  /// 提交图形码，请求下发短信验证码。
  Future<void> requestSecondAuthSMS(String graphicCode) async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    await c.requestSecondAuthSMS(graphicCode);
    notifyListeners();
  }

  /// 提交短信验证码完成二次认证并进入实时模式。
  Future<void> completeSecondAuth(String smsCode) async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    loading = true;
    notifyListeners();
    try {
      final u = await c.submitSecondAuth(smsCode);
      user = u;
      mode = SessionMode.live;
      _persistedLive = true;
      needsSecondAuth = false;
      lastError = null;
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSession, 1);
      await _refreshLive();
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 网页方式登录完成：吸收 WebView 会话 Cookie 并拉取用户信息。
  /// 校外门户被学校重定向进 WebVPN 网关时，WebView 会落在网关域上：
  /// 此时 CASTGC 已到手，先换网关票据再经网关读取门户。
  Future<bool> completeWebLogin(
    List<({String name, String value, String domain, String path})> cookies, {
    String userAgent = '',
    String userInfoJson = '',
  }) async {
    var c = _client;
    if (c == null) {
      c = PortalClient();
      _client = c;
    }
    c.setUserAgent(userAgent);
    c.absorbWebCookies(cookies);
    // WebView 里已拿到网关票据 → 直接进入网关模式（校外门户必须经网关读取）
    if (c.hasWebVPNTicket) c.webvpnOn = true;
    loading = true;
    notifyListeners();
    try {
      // 会话有效性：CASTGC / 门户 SESS_ID / 网关票据 任一在手即视为已登录
      if (!c.isLoggedIn && !c.hasCasSession && !c.hasWebVPNTicket) {
        lastError = '未能取得登录会话，请在页面中完成登录';
        return false;
      }
      if (!c.webvpnOn && !await c.ensureWebVPN()) {
        // 换票失败不阻断：校内直连场景仍可用
      }
      // 用户信息：优先用 WebView 内捕获的 userInfoDSL（真实页面，不被 WAF 拦），
      // 其次经网关拉门户 HTML，都失败则用学号占位（nidong 式：登录不阻断）
      PortalUser? u;
      if (userInfoJson.isNotEmpty && userInfoJson != '{}') {
        try {
          final decoded = jsonDecode(userInfoJson);
          if (decoded is Map) {
            final captured = PortalUser.fromInfoJson(Map<String, dynamic>.from(decoded));
            if (captured.hasProfile) u = captured;
          }
        } catch (_) {}
      }
      if (u == null || !u.hasCoreProfile) {
        try {
          final fetched = await c.fetchUserInfo();
          u = u?.merge(fetched) ?? fetched;
        } catch (_) {}
      }
      final p = await SharedPreferences.getInstance();
      if (userAgent.trim().isNotEmpty) {
        await p.setString(_kWebUa, userAgent.trim());
      }
      final sid = p.getString('cas.user') ?? '';
      user = u ??
          PortalUser(
            uid: '',
            name: sid.isEmpty ? '东大师生' : sid,
            sid: sid,
            identity: '',
            department: '',
            email: '',
            avatarUrl: '',
          );
      mode = SessionMode.live;
      _persistedLive = true;
      needsSecondAuth = false;
      lastError = null;
      await p.setInt(_kSession, 1);
      await _refreshLive();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 「保持登录」：密码只进本机安全存储（Android Keystore / iOS Keychain）。
  Future<void> saveCredentials(String username, String password) async {
    if (kIsWeb) return;
    try {
      await _secure.write(key: 'cas.user', value: username);
      await _secure.write(key: 'cas.pwd', value: password);
    } catch (_) {}
  }

  Future<void> clearCredentials() async {
    if (kIsWeb) return;
    try {
      await _secure.delete(key: 'cas.user');
      await _secure.delete(key: 'cas.pwd');
    } catch (_) {}
  }

  Future<(String, String)?> storedCredentials() async {
    if (kIsWeb) return null;
    try {
      final u = await _secure.read(key: 'cas.user');
      final p = await _secure.read(key: 'cas.pwd');
      if (u != null && p != null && u.isNotEmpty && p.isNotEmpty) {
        return (u, p);
      }
    } catch (_) {}
    return null;
  }

  /// App 启动时自动续登：上次是登录态且有保存的凭证 → 静默重登，全程免登录。
  Future<void> restoreSession() async {
    if (_restoring || loading || mode == SessionMode.live) return;
    if (!_persistedLive) return;
    final creds = await storedCredentials();
    if (creds == null) {
      // 无密码凭证：尝试网页登录留下的 WebView 持久化会话
      _restoring = true;
      try {
        final ok = await restoreWebSession();
        if (!ok) {
          lastError = '登录会话已过期，请重新登录';
        }
        notifyListeners();
      } finally {
        _restoring = false;
      }
      return;
    }
    _restoring = true;
    try {
      await login(creds.$1, creds.$2);
    } catch (_) {
      lastError = '自动续登失败（需要校园网或 VPN），当前为离线数据';
      notifyListeners();
    } finally {
      _restoring = false;
    }
  }

  /// 网页登录后的重启恢复：读取 WebView 持久化会话（无需密码）。
  Future<bool> restoreWebSession() async {
    final c = _client ??= PortalClient();
    try {
      final p = await SharedPreferences.getInstance();
      final ua = p.getString(_kWebUa) ?? '';
      if (ua.isNotEmpty) c.setUserAgent(ua);
      final cookies = await captureWebLoginCookies();
      if (cookies.isEmpty) return false;
      c.absorbWebCookies(cookies
          .map((ck) => (name: ck.name, value: ck.value, domain: ck.domain, path: ck.path))
          .toList());
      if (c.hasWebVPNTicket) c.webvpnOn = true;
      if (!c.isLoggedIn && !c.hasCasSession && !c.hasWebVPNTicket) return false;
      PortalUser? u;
      try {
        u = await c.fetchUserInfo();
      } catch (_) {
        u = null;
      }
      final sid = p.getString('cas.user') ?? '';
      user = u ??
          PortalUser(
            uid: '',
            name: sid.isEmpty ? '东大师生' : sid,
            sid: sid,
            identity: '',
            department: '',
            email: '',
            avatarUrl: '',
          );
      mode = SessionMode.live;
      _persistedLive = true;
      lastError = null;
      await p.setInt(_kSession, 1);
      await _refreshLive();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 退出登录：清除会话与保存的凭证（含 WebView 里的网页登录会话）。
  Future<void> logout() async {
    _client?.dispose();
    _client = null;
    needsSecondAuth = false;
    secondAuthCaptcha = null;
    try {
      await clearWebViewCookies();
    } catch (_) {}
    mode = SessionMode.demo;
    _persistedLive = false;
    needsSecondAuth = false;
    secondAuthCaptcha = null;
    user = PortalUser.demo;
    scheduleTemplate = demoSchedule;
    final cachedApps = await _loadAppsCache();
    apps = mergePortalApps([demoApps, cachedApps]);
    news = demoNews;
    todos = demoTodos;
    dataCards = demoDataCards;
    lastError = null;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSession, 0);
    await clearCredentials();
    notifyListeners();
  }

  void enterDemo() {
    _client?.dispose();
    _client = null;
    mode = SessionMode.demo;
    needsSecondAuth = false;
    secondAuthCaptcha = null;
    user = PortalUser.demo;
    scheduleTemplate = demoSchedule;
    apps = demoApps;
    unawaited(_loadAppsCache().then((cached) {
      if (cached.isNotEmpty && mode == SessionMode.demo) {
        apps = mergePortalApps([demoApps, cached]);
        notifyListeners();
      }
    }));
    news = demoNews;
    todos = demoTodos;
    dataCards = demoDataCards;
    lastError = null;
    notifyListeners();
  }

  Future<void> _refreshLive({bool refreshUser = false}) async {
    final c = _client;
    if (c == null) return;
    // 登录流程已经读取过资料；手动刷新时再重试，避免失败后连续重复换票。
    // 拉取 HTML 可能需要换网关票据，先补资料，再并行读取业务接口。
    if (refreshUser) {
      try {
        user = user.merge(await c.fetchUserInfo());
      } catch (_) {}
    }
    var ok = 0, total = 0;
    Future<void> guarded(Future<void> Function() f) async {
      total++;
      try {
        await f();
        ok++;
      } catch (_) {}
      notifyListeners();
    }

    await Future.wait([
      guarded(() async => scheduleTemplate =
          _templateFromOccurrences(await c.fetchWeek(DateTime.now()))),
      guarded(() async {
        final fetched = await c.fetchApps();
        apps = mergePortalApps([demoApps, await _loadAppsCache(), apps, fetched]);
        if (fetched.isNotEmpty) await _saveAppsCache(apps);
      }),
      guarded(() async => news = await c.fetchNews()),
      guarded(() async => todos = await c.fetchTodos()),
      guarded(() async => dataCards = await c.fetchDataCards()),
      guarded(() async => semesters = await c.fetchJwxtGrades()),
      guarded(() async => hotSearches = await c.fetchHotSearch()),
    ]);
    liveAvailable = total > 0 && ok >= 2;
    if (apps.isEmpty) {
      final cachedApps = await _loadAppsCache();
      apps = mergePortalApps([demoApps, cachedApps]);
    }
    lastError = liveAvailable ? null : '实时数据不可用（可能需要校园网或 VPN），已展示离线数据';
    notifyListeners();
  }

  /// 把某一周的真实事件归并成周模板。
  List<CourseSlot> _templateFromOccurrences(List<CourseOccurrence> occs) {
    if (occs.isEmpty) return demoSchedule;
    final merged = <String, CourseSlot>{};
    for (final o in occs) {
      merged.putIfAbsent(
        '${o.slot.weekday}-${o.slot.startMinutes}',
        () => o.slot,
      );
    }
    final list = merged.values.toList()
      ..sort((a, b) {
        final c = a.weekday.compareTo(b.weekday);
        return c != 0 ? c : a.startMinutes.compareTo(b.startMinutes);
      });
    return list.isEmpty ? demoSchedule : list;
  }

  Future<void> refresh() async {
    if (mode == SessionMode.live && _client != null) {
      await _refreshLive(refreshUser: true);
    } else {
      notifyListeners();
    }
  }

  /// 拉取某一周的真实课表事件（仅登录态可用）。
  Future<List<CourseOccurrence>> fetchWeek(DateTime anyDayInWeek) async {
    final c = _client;
    if (c == null) throw PortalException('未登录');
    return c.fetchWeek(anyDayInWeek);
  }

  /// e码通快捷入口：优先匹配门户应用列表，退回一卡通 SSO 地址。
  String get ecodeEntryUrl {
    for (final a in apps) {
      if (a.name.contains('e码通') || a.name.contains('校园码')) {
        final u = a.entryUrl();
        if (u.isNotEmpty) return u;
      }
    }
    for (final a in apps) {
      if (a.url.contains('ecard.neu.edu.cn')) {
        final u = a.entryUrl();
        if (u.isNotEmpty) return u;
      }
    }
    return withScheme('http://ecard.neu.edu.cn/selflogin/login.aspx');
  }

  /// WebView 注入用会话快照（未登录返回空）。
  Map<String, Map<String, String>> cookieSnapshot() {
    final c = _client;
    return c == null ? const {} : c.cookieSnapshot();
  }

  // ── 派生数据 ────────────────────────────────────────

  /// 某一天的完整日程：课程（按周次/假期过滤）+ 考试 + 用户日程，按时间排序。
  ///
  /// [liveWeek] 传入登录态下拉取的该周真实事件（可含考试/活动）。
  List<CourseOccurrence> agendaForDate(DateTime date,
      {List<CourseOccurrence>? liveWeek}) {
    final week = Semester.weekNumberOf(date);
    final out = <CourseOccurrence>[];

    // 1) 课程：登录态优先用真实周数据；离线用模板 + 周次/假期过滤
    final holiday = Semester.isHoliday(date);
    if (liveWeek != null) {
      for (final o in liveWeek) {
        if (o.date.year == date.year &&
            o.date.month == date.month &&
            o.date.day == date.day) {
          out.add(o);
        }
      }
    } else if (week >= 1 && week <= Semester.teachingWeeks && !holiday) {
      for (final s in scheduleTemplate) {
        if (s.weekday == date.weekday &&
            s.kind == 'course' &&
            s.coversWeek(week)) {
          out.add(CourseOccurrence(date, s));
        }
      }
    }

    // 2) 演示考试（离线模式；登录后门户会返回真实考试）
    if (mode == SessionMode.demo && liveWeek == null) {
      final iso = Semester.iso(date);
      for (final e in demoExams) {
        if (e.dateIso == iso) {
          out.add(CourseOccurrence(date, e.toSlot()));
        }
      }
    }

    // 3) 用户添加的日程（两种模式都生效）
    final iso = Semester.iso(date);
    for (final e in events) {
      if (e.dateIso == iso) {
        out.add(CourseOccurrence(date, e.toSlot()));
      }
    }

    out.sort((a, b) => a.slot.startMinutes.compareTo(b.slot.startMinutes));
    return out.mergeConsecutive();
  }

  List<CourseOccurrence> todayAgenda() => agendaForDate(DateTime.now());

  /// 当前或下一节课/日程（首页“接下来”提示）。
  CourseOccurrence? nextAgenda() {
    final now = DateTime.now();
    final cur = now.hour * 60 + now.minute;
    for (final o in todayAgenda()) {
      if (o.slot.endMinutes >= cur) return o;
    }
    return null;
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}

/// 简洁的状态注入（比 provider 依赖更轻）。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope not found');
    return s!.notifier!;
  }
}
