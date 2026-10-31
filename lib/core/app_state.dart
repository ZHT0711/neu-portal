/// 全局应用状态：会话、数据、主题设置。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_data.dart';
import 'models.dart';
import 'platform_style.dart';
import 'portal_client.dart';
import 'semester.dart';
import 'theme.dart';

enum SessionMode { live, demo }

class AppState extends ChangeNotifier {
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

  // ── 外观设置（持久化）───────────────────────────────
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = NeuColors.seed;
  bool useDynamicColor = false;
  PlatformStylePreference platformStyle = PlatformStylePreference.auto;

  static const _kMode = 'ui.themeMode';
  static const _kSeed = 'ui.seed';
  static const _kDyn = 'ui.dynamic';
  static const _kPlatform = 'ui.platform';
  static const _kEvents = 'planner.events';
  static const _kSession = 'session.mode';

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
    setPlatformPreference(platformStyle);
    _persistedLive = (p.getInt(_kSession) ?? 0) == 1;
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
    } catch (e) {
      lastError = e.toString();
      rethrow;
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
    if (creds == null) return;
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

  /// 退出登录：清除会话与保存的凭证。
  Future<void> logout() async {
    _client?.dispose();
    _client = null;
    mode = SessionMode.demo;
    _persistedLive = false;
    user = PortalUser.demo;
    scheduleTemplate = demoSchedule;
    apps = demoApps;
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
    user = PortalUser.demo;
    scheduleTemplate = demoSchedule;
    apps = demoApps;
    news = demoNews;
    todos = demoTodos;
    dataCards = demoDataCards;
    lastError = null;
    notifyListeners();
  }

  Future<void> _refreshLive() async {
    final c = _client;
    if (c == null) return;
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
      guarded(() async => apps = await c.fetchApps()),
      guarded(() async => news = await c.fetchNews()),
      guarded(() async => todos = await c.fetchTodos()),
      guarded(() async => dataCards = await c.fetchDataCards()),
      guarded(() async => semesters = await c.fetchJwxtGrades()),
      guarded(() async => hotSearches = await c.fetchHotSearch()),
    ]);
    liveAvailable = total > 0 && ok >= 2;
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
      await _refreshLive();
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
