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
import 'learning.dart';
import 'grade_report.dart';
import 'card.dart';
import 'web_cookies.dart';
import 'web_session.dart';
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
  bool _usesWebSession = false;
  bool get usesWebSession => _usesWebSession;
  String? sessionSaveError;
  Future<void> _sessionWrites = Future.value();
  int _sessionEpoch = 0;
  int _authAttempt = 0;
  Future<void>? _webSessionSave;
  Future<void>? _browserAccess;
  PortalClient? _accessClient;
  String? _savedWebSnapshot;
  bool _disposed = false;
  String? get webUserAgent => _client?.userAgent;

  SessionMode mode = SessionMode.demo;
  PortalUser user = PortalUser.demo;
  bool liveAvailable = false; // 登录后实时数据是否全部就绪

  List<CourseSlot> scheduleTemplate = demoSchedule;
  List<PortalApp> _apps = List.unmodifiable(demoApps);
  List<PortalApp> get apps => _apps;
  set apps(List<PortalApp> value) => _apps = List.unmodifiable(value);
  List<NewsItem> news = demoNews;
  List<TodoItem> todos = demoTodos;
  List<DataCard> dataCards = demoDataCards;
  List<ServiceSection> _services = List.unmodifiable(demoServices);
  List<ServiceSection> get services => _services;
  set services(List<ServiceSection> value) => _services = List.unmodifiable([
    for (final section in value)
      ServiceSection(section.name, List.unmodifiable(section.entries)),
  ]);
  List<GradeSemester> semesters = demoSemesters;

  final Map<LearningPlatform, LearningReport> learningReports = {};
  List<CGAssignment> cgAssignments = [];
  List<String> cgWarnings = [];
  CardBalance? cardBalance;
  DateTime? cardUpdatedAt;
  final Map<String, CardMonth> cardMonths = {};
  List<String> cardWarnings = [];
  String cardQueryMonth = learningDateText(DateTime.now()).substring(0, 7);
  bool gradesLoading = false;
  String? gradesError;
  List<String> failedGradeTerms = [];
  DateTime? gradesUpdatedAt;
  int _gradeRequest = 0;
  int _dataGeneration = 0;
  Future<void>? _portalRefresh;
  final _weeks = <DateTime, List<CourseOccurrence>>{};
  final _weekReads = <DateTime, Future<List<CourseOccurrence>>>{};
  int get dataGeneration => _dataGeneration;

  void _resetAccountData() {
    _dataGeneration++;
    _portalRefresh = null;
    _weeks.clear();
    _weekReads.clear();
    liveAvailable = false;
    _gradeRequest++;
    gradesLoading = false;
    gradesError = null;
    failedGradeTerms = [];
    gradesUpdatedAt = null;
    semesters = mode == SessionMode.demo ? demoSemesters : [];
    learningReports.clear();
    cgAssignments = [];
    cgWarnings = [];
    cardBalance = null;
    cardUpdatedAt = null;
    cardMonths.clear();
    cardWarnings = [];
    if (mode == SessionMode.live) {
      scheduleTemplate = [];
      news = [];
      todos = [];
      dataCards = [];
    }
  }

  void acceptLearningReport(LearningPlatform platform, LearningReport report) {
    learningReports[platform] = report.merging(learningReports[platform]);
    notifyListeners();
  }

  void acceptCGReport(Map report) {
    if (report['error'] != null) throw PortalException('${report['error']}');
    final rows = (report['assignments'] as List? ?? [])
        .whereType<Map>()
        .map(CGAssignment.new)
        .toList();
    if (rows.isEmpty) throw PortalException('未读取到 CG 作业，请完成登录后重试');
    cgAssignments = rows;
    cgWarnings = (report['warnings'] as List? ?? []).map((w) => '$w').toList();
    notifyListeners();
  }

  void acceptCardReport(Map report) {
    if (report['error'] != null) throw PortalException('${report['error']}');
    final balance = report['balance'];
    if (balance is Map) {
      cardBalance = CardBalance.fromJson(balance);
      cardUpdatedAt = DateTime.now();
    }
    final month = '${report['month']}';
    if (RegExp(r'^\d{4}-\d{2}$').hasMatch(month) && report['bills'] is List) {
      cardMonths[month] = CardMonth(
        month,
        (report['bills'] as List).whereType<Map>().map(CardBill.new).toList(),
        truncated: report['truncated'] == true,
      );
    }
    cardWarnings = (report['warnings'] as List? ?? [])
        .map((w) => '$w')
        .toList();
    if (balance is! Map && report['bills'] is! List) {
      notifyListeners();
      throw PortalException(
        cardWarnings.isEmpty ? '校园卡数据尚未读取' : cardWarnings.join('\n'),
      );
    }
    notifyListeners();
  }

  void acceptGradeReport(GradeReport report) {
    _gradeRequest++; // Browser results take precedence over an older HTTP query.
    gradesLoading = false;
    final merged = report.merging(semesters);
    semesters = merged.semesters;
    failedGradeTerms = merged.failedTerms;
    gradesError = null;
    gradesUpdatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> loadGrades({bool force = false}) async {
    final c = _client;
    if (mode != SessionMode.live ||
        c == null ||
        gradesLoading ||
        (!force && gradesUpdatedAt != null)) {
      return;
    }
    final generation = _dataGeneration;
    final request = ++_gradeRequest;
    gradesLoading = true;
    gradesError = null;
    notifyListeners();
    bool current() =>
        !_disposed &&
        generation == _dataGeneration &&
        request == _gradeRequest &&
        c == _client &&
        mode == SessionMode.live;
    try {
      final report = await c.fetchGradeReport();
      if (!current()) return;
      final merged = report.merging(semesters);
      semesters = merged.semesters;
      failedGradeTerms = merged.failedTerms;
      gradesUpdatedAt = DateTime.now();
    } catch (e) {
      if (current()) gradesError = '$e';
    } finally {
      if (current()) {
        gradesLoading = false;
        notifyListeners();
      }
    }
  }
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
    unawaited(persistWebSession());
  }

  // ── 外观设置（持久化）───────────────────────────────
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = NeuColors.seed;
  bool useDynamicColor = false;
  PlatformStylePreference platformStyle = PlatformStylePreference.auto;
  LiquidTabBarMode liquidTabBarMode = LiquidTabBarMode.native;
  AccessMode accessMode = AccessMode.auto;
  bool switchingAccess = false;
  bool _accessReady = false;

  String get accessStatus => _accessReady
      ? '当前线路为${_client?.webvpnOn == true ? ' WebVPN' : '直连'}'
      : '校内直连，校外自动使用 WebVPN';

  static const _kMode = 'ui.themeMode';
  static const _kSeed = 'ui.seed';
  static const _kDyn = 'ui.dynamic';
  static const _kPlatform = 'ui.platform';
  static const _kGlassMode = 'ui.liquidTabBarMode';
  static const _kAccessMode = 'network.accessMode';
  static const _kEvents = 'planner.events';
  static const _kSession = 'session.mode';
  static const _kAppsCache = 'cache.apps';
  static const _kWebUa = 'session.webUserAgent';
  static const _kWebSession = 'session.web.v1';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Serialized with deletion so an in-flight background save cannot undo logout.
  Future<void> persistWebSession() {
    final epoch = _sessionEpoch;
    if (kIsWeb || !_persistedLive || mode != SessionMode.live) {
      return Future.value();
    }
    if (_webSessionSave case final pending?) return pending;
    final save = _sessionWrites.then((_) async {
      if (epoch != _sessionEpoch || !_persistedLive || _disposed) return;
      final oldError = sessionSaveError;
      try {
        final c = _client;
        if (c == null) return;
        final native = _usesWebSession ? await readNativeSessionCookies() : null;
        if (epoch != _sessionEpoch || !_persistedLive || c != _client) return;
        if (native != null) c.restoreSessionCookies(native);
        if (!c.hasLoginSession) return;
        final snapshot = jsonEncode({
          'version': 1,
          'web': _usesWebSession,
          'user': user.toInfoJson(),
          'userAgent': c.userAgent ?? '',
          'cookies': c.sessionCookies(),
        });
        if (_savedWebSnapshot != snapshot) {
          await _secure.write(
            key: _kWebSession,
            value: snapshot,
            iOptions: const IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
        }
        if (epoch != _sessionEpoch || _disposed) return;
        _savedWebSnapshot = snapshot;
        sessionSaveError = null;
      } catch (_) {
        if (epoch != _sessionEpoch || _disposed) return;
        sessionSaveError = '登录会话保存失败，重启后可能需要重新登录';
      }
      if (oldError != sessionSaveError) notifyListeners();
    }).whenComplete(() {
      if (epoch == _sessionEpoch) _webSessionSave = null;
    });
    _webSessionSave = save;
    return _sessionWrites = save;
  }

  void _resetWebSave() {
    _sessionEpoch++;
    _webSessionSave = null;
    _savedWebSnapshot = null;
  }

  Future<void> _clearWebSession() {
    _resetWebSave();
    _resetAccountData();
    return _sessionWrites = _sessionWrites
        .then((_) async {
          if (!kIsWeb) await _secure.delete(key: _kWebSession);
        })
        .catchError((Object _) {});
  }

  /// 上次是否处于登录态（重启后自动续登用）。
  bool _persistedLive = false;
  Future<void>? _sessionRestore;

  Future<void> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final savedAccess = p.getString(_kAccessMode);
    accessMode = AccessMode.values.firstWhere(
      (value) => value.name == savedAccess,
      orElse: () => AccessMode.auto,
    );
    _client?.accessMode = accessMode;
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

  Future<void> setAccessMode(AccessMode value) async {
    if (switchingAccess || accessMode == value) return;
    switchingAccess = true;
    accessMode = value;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kAccessMode, value.name);
      final c = _client ??= PortalClient();
      c.accessMode = value;
      await prepareBrowserAccess(force: true);
      if (mode == SessionMode.live) await refresh();
    } finally {
      switchingAccess = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 在新页面与前台恢复时重选线路，并把新网关票据同步到原生浏览器。
  Future<void> prepareBrowserAccess({bool force = false}) {
    if (_disposed) return Future.value();
    final c = _client ??= PortalClient()..accessMode = accessMode;
    if (_accessClient == c && _browserAccess != null) return _browserAccess!;
    if (force) c.invalidateAccessRoute();
    _accessClient = c;
    return _browserAccess = _prepareBrowserAccess(c).whenComplete(() {
      if (_accessClient == c) {
        _accessClient = null;
        _browserAccess = null;
      }
    });
  }

  Future<void> _prepareBrowserAccess(PortalClient c) async {
    final status = accessStatus;
    final native = _usesWebSession ? await readNativeSessionCookies() : null;
    if (c != _client || _disposed) return;
    if (native != null) c.restoreSessionCookies(native);
    final previous = {
      for (final cookie in native ?? c.sessionCookies())
        sessionCookieKey(cookie): cookie['value'],
    };
    await c.prepareAccess();
    if (c != _client || _disposed) return;
    final updated = c.sessionCookies().where((cookie) =>
        cookie['metadataKnown'] == true &&
        previous[sessionCookieKey(cookie)] != cookie['value']).toList();
    if (updated.isNotEmpty) await restoreNativeSessionCookies(updated);
    if (c != _client || _disposed) return;
    _accessReady = true;
    if (accessStatus != status) notifyListeners();
  }

  void invalidateAccessRoute() => _client?.invalidateAccessRoute();

  Future<void> resumeSession() async {
    invalidateAccessRoute();
    final c = _client;
    if (c == null || mode != SessionMode.live || loading) return;
    final attempt = _authAttempt;
    final wasOnGateway = c.webvpnOn;
    try {
      await prepareBrowserAccess();
      if (!_ownsAuth(attempt) || c != _client) return;
      if (wasOnGateway != c.webvpnOn || !liveAvailable) {
        await _refreshLive(refreshUser: true);
      }
      if (_ownsAuth(attempt)) await persistWebSession();
    } catch (_) {
      // 前台恢复失败时仍保留会话，等下一次请求或手动刷新。
    }
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
  bool _ownsAuth(int attempt) => !_disposed && attempt == _authAttempt;

  void _checkAuth(int attempt) {
    if (!_ownsAuth(attempt)) throw PortalException('登录操作已结束，请重试');
  }

  void _adoptLogin(PortalUser profile, {required bool web, bool keepSession = true}) {
    user = profile;
    mode = SessionMode.live;
    _usesWebSession = web;
    _persistedLive = keepSession;
    needsSecondAuth = false;
    secondAuthCaptcha = null;
    lastError = null;
    _resetAccountData();
  }

  Future<void> login(String username, String password, {bool keepSession = false}) async {
    final attempt = ++_authAttempt;
    _resetAccountData();
    _usesWebSession = false;
    _accessReady = false;
    loading = true;
    lastError = null;
    needsSecondAuth = false;
    notifyListeners();
    try {
      _client?.dispose();
      final c = PortalClient()..accessMode = accessMode;
      _client = c;
      final profile = await c.login(username, password);
      _checkAuth(attempt);
      await _finishPasswordLogin(profile, attempt, keepSession: keepSession);
    } on SecondAuthRequired {
      if (_ownsAuth(attempt)) {
        needsSecondAuth = true;
        lastError = null;
      }
      rethrow;
    } catch (e) {
      if (_ownsAuth(attempt)) lastError = e.toString();
      rethrow;
    } finally {
      if (_ownsAuth(attempt)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _finishPasswordLogin(
    PortalUser profile,
    int attempt, {
    required bool keepSession,
  }) async {
    await _clearWebSession();
    _checkAuth(attempt);
    final preferences = await SharedPreferences.getInstance();
    _checkAuth(attempt);
    await preferences.setInt(_kSession, keepSession ? 1 : 0);
    _checkAuth(attempt);
    _adoptLogin(profile, web: false, keepSession: keepSession);
    await persistWebSession();
    _checkAuth(attempt);
    unawaited(_refreshLive());
  }

  /// 拉取二次认证图形码。
  Future<void> loadSecondAuthCaptcha() async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    final attempt = _authAttempt;
    final captcha = await c.fetchSecondAuthCaptcha();
    _checkAuth(attempt);
    secondAuthCaptcha = captcha;
    notifyListeners();
  }

  /// 提交图形码，请求下发短信验证码。
  Future<void> requestSecondAuthSMS(String graphicCode) async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    final attempt = _authAttempt;
    await c.requestSecondAuthSMS(graphicCode);
    _checkAuth(attempt);
  }

  /// 提交短信验证码完成二次认证并进入实时模式。
  Future<void> completeSecondAuth(String smsCode, {bool keepSession = false}) async {
    final c = _client;
    if (c == null) throw PortalException('当前没有待验证的登录，请先登录');
    final attempt = ++_authAttempt;
    loading = true;
    notifyListeners();
    try {
      final profile = await c.submitSecondAuth(smsCode);
      _checkAuth(attempt);
      await _finishPasswordLogin(profile, attempt, keepSession: keepSession);
    } catch (e) {
      if (_ownsAuth(attempt)) lastError = e.toString();
      rethrow;
    } finally {
      if (_ownsAuth(attempt)) {
        loading = false;
        notifyListeners();
      }
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
    final attempt = ++_authAttempt;
    _resetWebSave();
    final c = _client ??= PortalClient()..accessMode = accessMode;
    c.setUserAgent(userAgent);
    c.absorbWebCookies(cookies);
    loading = true;
    notifyListeners();
    try {
      if (!c.hasLoginSession) {
        lastError = '未能取得登录会话，请在页面中完成登录';
        return false;
      }
      await prepareBrowserAccess();
      _checkAuth(attempt);
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
      _checkAuth(attempt);
      final p = await SharedPreferences.getInstance();
      _checkAuth(attempt);
      final ua = userAgent.trim();
      if (ua.isNotEmpty) await p.setString(_kWebUa, ua);
      _checkAuth(attempt);
      await p.setInt(_kSession, 1);
      _checkAuth(attempt);
      _adoptLogin(u ?? _placeholderProfile(p), web: true);
      await persistWebSession();
      _checkAuth(attempt);
      unawaited(_refreshLive());
      return true;
    } catch (e) {
      if (_ownsAuth(attempt)) lastError = e.toString();
      return false;
    } finally {
      if (_ownsAuth(attempt)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  PortalUser _placeholderProfile(SharedPreferences preferences) {
    final sid = preferences.getString('cas.user') ?? '';
    return PortalUser(
      uid: '',
      name: sid.isEmpty ? '东大师生' : sid,
      sid: sid,
      identity: '',
      department: '',
      email: '',
      avatarUrl: '',
    );
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
  Future<void> restoreSession() {
    if (_sessionRestore case final pending?) return pending;
    if (_disposed || loading || mode == SessionMode.live || !_persistedLive) {
      return Future.value();
    }
    final attempt = _authAttempt;
    return _sessionRestore = _restoreSession(attempt).whenComplete(() {
      _sessionRestore = null;
    });
  }

  Future<void> _restoreSession(int attempt) async {
    if (await restoreWebSession()) return;
    if (!_ownsAuth(attempt)) return;
    final credentials = await storedCredentials();
    if (!_ownsAuth(attempt)) return;
    if (credentials == null) {
      lastError = '登录会话已过期，请重新登录';
      notifyListeners();
      return;
    }
    final loginAttempt = _authAttempt + 1;
    try {
      await login(credentials.$1, credentials.$2, keepSession: true);
    } catch (_) {
      if (!_ownsAuth(loginAttempt)) return;
      lastError = '自动续登失败（需要校园网或 VPN），当前为离线数据';
      notifyListeners();
    }
  }

  /// 优先恢复已保存的会话。当前线路需要认证时仍保留其它线路的会话。
  Future<bool> restoreWebSession() async {
    final attempt = _authAttempt;
    final c = _client ??= PortalClient()..accessMode = accessMode;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = kIsWeb ? null : await _secure.read(key: _kWebSession);
      _checkAuth(attempt);
      var profile = _placeholderProfile(p);
      var web = true;
      if (raw != null) {
        final saved = jsonDecode(raw) as Map;
        if (saved['version'] != 1) return false;
        web = saved['web'] != false;
        final cookies = (saved['cookies'] as List)
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        profile = PortalUser.fromInfoJson(
          Map<String, dynamic>.from(saved['user'] as Map),
        );
        c.restoreSessionCookies(cookies);
        c.setUserAgent('${saved['userAgent'] ?? ''}');
      } else {
        final ua = p.getString(_kWebUa) ?? '';
        if (ua.isNotEmpty) c.setUserAgent(ua);
        final cookies = await captureWebLoginCookies();
        _checkAuth(attempt);
        if (cookies.isEmpty) return false;
        c.absorbWebCookies(cookies
            .map((ck) => (name: ck.name, value: ck.value, domain: ck.domain, path: ck.path))
            .toList());
      }
      c.adoptGatewayTicket();
      if (!c.hasLoginSession) {
        if (raw != null) await _clearWebSession();
        return false;
      }
      PortalUser? fresh;
      var authenticationRequired = false;
      try {
        fresh = await c.validateSavedSession();
      } on PortalException catch (e) {
        authenticationRequired = e.sessionExpired;
      } catch (_) {
        // A transient connection failure does not invalidate the browser session.
      }
      _checkAuth(attempt);
      if (raw != null) {
        await restoreNativeSessionCookies(c.sessionCookies());
      } else {
        await p.setInt(_kSession, 1);
      }
      _checkAuth(attempt);
      _savedWebSnapshot = raw;
      _adoptLogin(fresh == null ? profile : profile.merge(fresh), web: web);
      if (fresh == null) {
        lastError = authenticationRequired
            ? '当前线路需要重新认证，已保留上次登录会话'
            : '暂时无法连接门户，已恢复上次登录会话';
      } else {
        unawaited(_refreshLive().then((_) async {
          if (_ownsAuth(attempt)) await persistWebSession();
        }));
      }
      unawaited(persistWebSession());
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 退出登录：清除会话与保存的凭证（含 WebView 里的网页登录会话）。
  Future<void> logout() async {
    _authAttempt++;
    loading = false;
    _usesWebSession = false;
    await _clearWebSession();
    sessionSaveError = null;
    _client?.dispose();
    _client = null;
    _accessReady = false;
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
    semesters = demoSemesters;
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
    _authAttempt++;
    _resetWebSave();
    loading = false;
    _resetAccountData();
    _usesWebSession = false;
    _client?.dispose();
    _client = null;
    _accessReady = false;
    mode = SessionMode.demo;
    needsSecondAuth = false;
    secondAuthCaptcha = null;
    user = PortalUser.demo;
    semesters = demoSemesters;
    scheduleTemplate = demoSchedule;
    apps = demoApps;
    unawaited(_loadAppsCache().then((cached) {
      if (!_disposed && cached.isNotEmpty && mode == SessionMode.demo) {
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

  Timer? _notifyTimer;

  /// 刷新期间多路请求相继返回，合并成一次重建，避免全部页签连续重建。
  void _notifyCoalesced() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 120), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _flushCoalesced() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
  }

  Future<void> _refreshLive({bool refreshUser = false}) {
    if (_portalRefresh != null) return _portalRefresh!;
    final generation = _dataGeneration;
    return _portalRefresh = _performRefreshLive(refreshUser: refreshUser)
        .whenComplete(() {
          if (generation == _dataGeneration) _portalRefresh = null;
        });
  }

  Future<void> _performRefreshLive({bool refreshUser = false}) async {
    final c = _client;
    if (c == null) return;
    final generation = _dataGeneration;
    bool current() =>
        !_disposed &&
        c == _client &&
        generation == _dataGeneration &&
        mode == SessionMode.live;
    try {
      await prepareBrowserAccess();
    } catch (_) {
      // Individual portal reads can still succeed on the current route.
    }
    if (!current()) return;
    final baseline = {
      for (final cookie in c.sessionCookies()) sessionCookieKey(cookie): cookie['value'],
    };
    if (refreshUser) {
      try {
        final profile = await c.fetchUserInfo();
        if (!current()) return;
        final merged = user.merge(profile);
        if ((user.uid.isNotEmpty &&
                merged.uid.isNotEmpty &&
                user.uid != merged.uid) ||
            (user.sid.isNotEmpty &&
                merged.sid.isNotEmpty &&
                user.sid != merged.sid)) {
          _resetAccountData();
          user = merged;
          await _refreshLive();
          return;
        }
        user = merged;
      } catch (_) {}
    }
    var ok = 0, total = 0;
    Future<void> guarded<T>(
      Future<T> Function() fetch,
      void Function(T) apply,
    ) async {
      total++;
      try {
        final value = await fetch();
        if (!current()) return;
        apply(value);
        ok++;
      } catch (_) {}
      if (current()) _notifyCoalesced();
    }

    await Future.wait([
      guarded(
        () => fetchWeek(DateTime.now(), force: refreshUser),
        (value) => scheduleTemplate = _templateFromOccurrences(value),
      ),
      guarded(c.fetchApps, (value) {
        apps = mergePortalApps([demoApps, apps, value]);
        if (value.isNotEmpty) unawaited(_saveAppsCache(apps));
      }),
      guarded(c.fetchNews, (value) => news = value),
      guarded(c.fetchTodos, (value) => todos = value),
      guarded(c.fetchDataCards, (value) => dataCards = value),
      guarded(c.fetchHotSearch, (value) => hotSearches = value),
    ]);
    _flushCoalesced();
    if (!current()) return;
    final renewed = c.sessionCookies().where((cookie) =>
        cookie['metadataKnown'] == true &&
        baseline[sessionCookieKey(cookie)] != cookie['value']).toList();
    if (renewed.isNotEmpty) {
      try {
        await restoreNativeSessionCookies(renewed);
      } catch (_) {}
      if (!current()) return;
    }
    liveAvailable = total > 0 && ok >= 2;
    lastError = liveAvailable ? null : '实时数据暂不可用，请检查线路后重试';
    notifyListeners();
  }
  /// 把某一周的真实事件归并成周模板。
  List<CourseSlot> _templateFromOccurrences(List<CourseOccurrence> occs) {
    if (occs.isEmpty) return [];
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
    return list;
  }

  Future<void> refresh() async {
    if (mode == SessionMode.live && _client != null) {
      invalidateAccessRoute();
      await _refreshLive(refreshUser: true);
      await persistWebSession();
    } else {
      notifyListeners();
    }
  }

  static DateTime _weekStart(DateTime day) =>
      DateTime(day.year, day.month, day.day - day.weekday % 7);

  List<CourseOccurrence>? cachedWeek(DateTime day) => _weeks[_weekStart(day)];

  /// 首页和课表页共享当前账号的同周请求和结果。
  Future<List<CourseOccurrence>> fetchWeek(
    DateTime anyDayInWeek, {
    bool force = false,
  }) async {
    final c = _client;
    if (c == null || mode != SessionMode.live) throw PortalException('未登录');
    final start = _weekStart(anyDayInWeek);
    if (_weekReads[start] case final pending?) return pending;
    if (!force && _weeks[start] != null) return _weeks[start]!;
    final generation = _dataGeneration;
    final read = Future.sync(() => c.fetchWeek(start)).then((result) {
      if (_disposed || c != _client || generation != _dataGeneration ||
          mode != SessionMode.live) {
        throw PortalException('账号已切换，请重新读取课表');
      }
      final snapshot = List<CourseOccurrence>.unmodifiable(result);
      _weeks.remove(start);
      _weeks[start] = snapshot;
      if (_weeks.length > 24) _weeks.remove(_weeks.keys.first);
      return snapshot;
    }).whenComplete(() {
      if (generation == _dataGeneration) _weekReads.remove(start);
    });
    _weekReads[start] = read;
    return read;
  }

  /// e码通快捷入口：优先匹配门户应用列表，退回一卡通 SSO 地址。
  String get cgEntryUrl {
    for (final app in apps) {
      final url = app.entryUrl();
      if (LearningPlatform.cg.accepts(url)) return url;
    }
    return LearningPlatform.cg.entryUrl;
  }

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

  List<({String name, String value, String domain, String path})> browserCookies() =>
      _client?.browserCookies() ?? const [];

  String browserURL(String url) => _client?.maybeWrap(url) ?? url;

  void updateWebProfile(PortalUser captured) {
    if (mode != SessionMode.live || !captured.hasProfile) return;
    final merged = user.merge(captured);
    if ((user.uid.isNotEmpty && merged.uid.isNotEmpty && user.uid != merged.uid) ||
        (user.sid.isNotEmpty && merged.sid.isNotEmpty && user.sid != merged.sid)) {
      _resetAccountData();
    }
    user = merged;
    unawaited(persistWebSession());
    notifyListeners();
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
    _disposed = true;
    _notifyTimer?.cancel();
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
