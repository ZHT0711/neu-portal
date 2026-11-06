import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/platform_style.dart';
import '../core/ios_glass.dart';
import 'package:flutter/cupertino.dart';
import '../core/demo_data.dart';
import '../core/models.dart';
import '../core/semester.dart';
import '../core/tab_scroller.dart';
import '../core/theme.dart';
import 'webview_page.dart';

/// 课表 — 教务规范节次网格（第1-2节…第9-10节）+ 周次标注
/// + 学期模型（教学周/考试周/假期）+ 添加日程（本机 / 门户）。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static final DateTime _anchorWeekStart = DateTime(2026, 10, 25);
  static const int _anchorWeekNumber = kAnchorWeekNumber;
  static const double _rowH = 92; // 一个大节（2 小节）行高

  int _offset = 0; // 相对锚点周的偏移
  bool _fitToScreen = true; // 默认整周一屏，无需横向/纵向滑动
  final _scroll = ScrollController();
  final Map<String, List<CourseOccurrence>> _remoteCache = {};
  bool _fetching = false;
  bool _fetchFailed = false;
  int? _accountGeneration;

  DateTime get _weekStart => _anchorWeekStart.add(Duration(days: 7 * _offset));
  int get _weekNumber => _anchorWeekNumber + _offset;
  bool get _isCurrent => _offset == _currentWeekOffset(DateTime.now());

  static int _currentWeekOffset(DateTime now) {
    final ws = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7));
    return (ws.difference(_anchorWeekStart).inDays / 7).round();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TabScroller.attach(1, _scroll);
      _maybeFetch();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final generation = AppScope.of(context).dataGeneration;
    if (_accountGeneration == generation) return;
    _accountGeneration = generation;
    _remoteCache.clear();
    _fetching = false;
    _fetchFailed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFetch();
    });
  }

  @override
  void dispose() {
    TabScroller.detach(1, _scroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _maybeFetch() async {
    final s = AppScope.of(context);
    if (s.mode != SessionMode.live) return;
    final key = Semester.iso(_weekStart);
    final generation = s.dataGeneration;
    bool current() => mounted && generation == s.dataGeneration;
    if (_remoteCache.containsKey(key) || _fetching) return;
    setState(() => _fetching = true);
    try {
      final occs = await s.fetchWeek(_weekStart);
      if (!current()) return;
      _remoteCache[key] = occs;
      _fetchFailed = false;
    } catch (_) {
      if (current()) _fetchFailed = true;
    } finally {
      if (current()) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final week = _weekNumber;
    final liveKey = Semester.iso(_weekStart);

    // 每天的聚合日程（周一..周日）
    final days = List<List<CourseOccurrence>>.generate(7, (i) {
      final d = i == 6 ? _weekStart : _weekStart.add(Duration(days: i + 1));
      return s.agendaForDate(d, liveWeek: _remoteCache[liveKey]);
    });

    final weekSwitcher = _WeekSwitcher(
      weekNumber: week,
      rangeText:
          '${Fmt.monthDay(_weekStart)} – ${Fmt.monthDay(_weekStart.add(const Duration(days: 6)))}',
      isCurrent: _isCurrent,
      onPrev: () {
        setState(() {
          _offset--;
          _fetchFailed = false;
        });
        _maybeFetch();
      },
      onNext: () {
        setState(() {
          _offset++;
          _fetchFailed = false;
        });
        _maybeFetch();
      },
      onBackToCurrent: () {
        setState(() {
          _offset = _currentWeekOffset(DateTime.now());
          _fetchFailed = false;
        });
        _maybeFetch();
      },
    );

    if (!isApple) {
      return Scaffold(
        appBar: PageAppBar(
          title: '课表',
          actions: [
            Tooltip(
              message: _fitToScreen ? '切换为滑动展开' : '切换为整周一屏',
              child: IconButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _fitToScreen = !_fitToScreen);
                },
                icon: Icon(_fitToScreen
                    ? Icons.fit_screen
                    : Icons.view_week_outlined),
              ),
            ),
            if (_fetching)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_fetchFailed)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Tooltip(
                  message: '实时数据获取失败，已展示推算课表',
                  child: Icon(Icons.cloud_off, size: 18, color: scheme.outline),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showEventForm(context),
          icon: const Icon(Icons.add),
          label: const Text('添加日程'),
        ),
        body: Column(
          children: [
            weekSwitcher,
            _SemesterBanner(week: week),
            _ScheduleModeBar(
              fitToScreen: _fitToScreen,
              onToggle: () {
                HapticFeedback.selectionClick();
                setState(() => _fitToScreen = !_fitToScreen);
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.only(bottom: portalBottomInset(context)),
                child: LayoutBuilder(
                  builder: (context, constraints) => _fitToScreen
                      ? SizedBox(
                          width: constraints.maxWidth,
                          child: _Grid(
                            days: days,
                            weekStart: _weekStart,
                            today: today,
                            isCurrentWeek: _isCurrent,
                            fitToScreen: true,
                            rowHeight: 60.0,
                            onEventTap: (occ) => _showDetail(context, occ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: constraints.maxWidth.clamp(
                                680 * MediaQuery.textScalerOf(context).scale(1),
                                double.infinity),
                            child: _Grid(
                              days: days,
                              weekStart: _weekStart,
                              today: today,
                              isCurrentWeek: _isCurrent,
                              fitToScreen: false,
                              rowHeight: 92.0,
                              onEventTap: (occ) => _showDetail(context, occ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            backgroundColor: CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context)
                .withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.80
                        : 0.72),
            border: Border(
              bottom: BorderSide(
                color: IosColors.separator(
                        Theme.of(context).brightness == Brightness.dark)
                    .withValues(alpha: 0.35),
                width: 0.5,
              ),
            ),
            largeTitle: const Text('课表'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _fitToScreen = !_fitToScreen);
                  },
                  child: Semantics(
                    label: _fitToScreen ? '切换为滑动展开' : '切换为整周一屏',
                    button: true,
                    child: Icon(
                      _fitToScreen
                          ? CupertinoIcons.rectangle_grid_1x2
                          : CupertinoIcons.viewfinder,
                      size: 20,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: () => _showEventForm(context),
                  child: Semantics(
                    label: '添加日程',
                    button: true,
                    child: const Icon(CupertinoIcons.add, size: 22),
                  ),
                ),
                if (_fetching)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CupertinoActivityIndicator(radius: 7),
                    ),
                  )
                else if (_fetchFailed)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: '实时数据获取失败，已展示推算课表',
                      child: Icon(Icons.cloud_off,
                          size: 18, color: scheme.outline),
                    ),
                  ),
              ],
            ),
            transitionBetweenRoutes: false,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  weekSwitcher,
                  const SizedBox(height: 8),
                  _SemesterBanner(week: week),
                  _ScheduleModeBar(
                    fitToScreen: _fitToScreen,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      setState(() => _fitToScreen = !_fitToScreen);
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: portalBottomInset(context)),
              child: LayoutBuilder(
                builder: (context, constraints) => _fitToScreen
                    ? SizedBox(
                        width: constraints.maxWidth,
                        child: _Grid(
                          days: days,
                          weekStart: _weekStart,
                          today: today,
                          isCurrentWeek: _isCurrent,
                          fitToScreen: true,
                          rowHeight: 60.0,
                          onEventTap: (occ) => _showDetail(context, occ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: constraints.maxWidth.clamp(
                              680 * MediaQuery.textScalerOf(context).scale(1),
                              double.infinity),
                          child: _Grid(
                            days: days,
                            weekStart: _weekStart,
                            today: today,
                            isCurrentWeek: _isCurrent,
                            fitToScreen: false,
                            rowHeight: 92.0,
                            onEventTap: (occ) => _showDetail(context, occ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 添加日程 ─────────────────────────────────────────────
  Future<void> _showEventForm(BuildContext context,
      {DateTime? initialDate}) async {
    final s = AppScope.of(context);
    String kind = 'custom';
    DateTime date = initialDate ?? DateTime.now();
    TimeOfDay start = const TimeOfDay(hour: 19, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 20, minute: 0);

    Future<void> pickDate() async {
      final d = await pickPlatformDate(context, date);
      if (d != null) date = d;
    }

    Future<void> pickTime(bool isStart) async {
      final t = await pickPlatformTime(context, isStart ? start : end);
      if (t == null) return;
      if (isStart) {
        start = t;
        if (t.hour * 60 + t.minute >= end.hour * 60 + end.minute) {
          final minutes = (t.hour * 60 + t.minute + 45).clamp(0, 1439);
          end = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
        }
      } else {
        end = t;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: !isApple,
      useSafeArea: true,
      builder: (ctx) => _EventFormControllers(
          builder: (ctx, nameCtrl, roomCtrl) => StatefulBuilder(
                builder: (ctx, setSheet) => SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, isApple ? 16 : 0, 22,
                        22 + MediaQuery.of(ctx).viewInsets.bottom),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text('添加日程',
                                  style: Theme.of(ctx).textTheme.titleLarge)),
                          if (isApple)
                            CupertinoButton(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('取消')),
                        ]),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.edit_note),
                            labelText: '标题',
                            hintText: '如：高数期中考试、实验室例会',
                          ),
                        ),
                        const SizedBox(height: 12),
                        AdaptiveSegments<String>(
                          values: const {'custom': '日程', 'exam': '考试'},
                          selected: kind,
                          onChanged: (value) => setSheet(() => kind = value),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _PickTile(
                                icon: Icons.event,
                                label: '日期',
                                value: '${date.month}/${date.day}',
                                onTap: () async {
                                  await pickDate();
                                  if (ctx.mounted) setSheet(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PickTile(
                                icon: Icons.schedule,
                                label: '开始',
                                value: start.format(ctx),
                                onTap: () async {
                                  await pickTime(true);
                                  if (ctx.mounted) setSheet(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PickTile(
                                icon: Icons.schedule,
                                label: '结束',
                                value: end.format(ctx),
                                onTap: () async {
                                  await pickTime(false);
                                  if (ctx.mounted) setSheet(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: roomCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.place),
                            labelText: '地点（可选）',
                          ),
                        ),
                        const SizedBox(height: 18),
                        AdaptiveFilledButton(
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            final sm = start.hour * 60 + start.minute;
                            final em = end.hour * 60 + end.minute;
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('请填写标题')));
                              return;
                            }
                            if (em <= sm) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('结束时间要晚于开始时间')));
                              return;
                            }
                            HapticFeedback.lightImpact();
                            s.addEvent(PlannerEvent(
                              id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
                              name: name,
                              dateIso: Semester.iso(date),
                              startMinutes: sm,
                              endMinutes: em,
                              room: roomCtrl.text.trim(),
                              kind: kind,
                            ));
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('已添加到本机课表，首页同步可见')));
                          },
                          child: const Text('保存到本机课表'),
                        ),
                        if (s.mode == SessionMode.live) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const WebViewPage(
                                  title: '门户日程（官方）',
                                  url:
                                      'https://personal.neu.edu.cn/portal/pages/schedulesite/site/home?from=neu',
                                ),
                              ));
                            },
                            icon: const Icon(Icons.sync_alt, size: 18),
                            label: const Text('在门户日程中添加（官方·含提醒/重复）'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          s.mode == SessionMode.live
                              ? '本机日程即时显示在课表与首页；需官方提醒/重复请用门户日程'
                              : '离线模式下日程仅保存在本机；登录门户后可用官方日程同步',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  Theme.of(ctx).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
    );
  }

  // ── 日程详情 ─────────────────────────────────────────────
  void _showDetail(BuildContext context, CourseOccurrence occ) {
    HapticFeedback.lightImpact();
    final s = AppScope.of(context);
    final slot = occ.slot;
    final event = _findEvent(s, occ);
    final deletable = event?.deletable ?? false;
    final sp = Semester.startPeriodOf(slot.startMinutes);
    final ep = Semester.endPeriodOf(slot.endMinutes);

    showModalBottomSheet(
      context: context,
      showDragHandle: !isApple,
      useSafeArea: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final tone = NeuColors.adaptiveTone(context, NeuColors.slotTone(slot));
        final weekText = slot.weekStart > 0 && slot.weekEnd < 99
            ? (slot.weekStart == slot.weekEnd
                ? '第${slot.weekStart}周'
                : '第${slot.weekStart}-${slot.weekEnd}周')
            : null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration:
                          BoxDecoration(color: tone, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    if (slot.kind != 'course') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          slot.kind == 'exam' ? '考试' : '本机日程',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: tone),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        slot.name,
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _detailRow(ctx, Icons.schedule, '节次',
                    '第$sp-${ep == sp ? sp : ep}节（${Semester.hm(slot.startMinutes)}–${Semester.hm(slot.endMinutes)}）'),
                if (weekText != null)
                  _detailRow(ctx, Icons.date_range, '周次', weekText),
                _detailRow(ctx, Icons.place, '地点', slot.room),
                if (event?.note.isNotEmpty == true)
                  _detailRow(
                      ctx, Icons.sticky_note_2_outlined, '备注', event!.note),
                const SizedBox(height: 8),
                if (deletable && event != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      s.removeEvent(event.id);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已删除：${event.name}')));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(
                          color: scheme.error.withValues(alpha: 0.4)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除此日程'),
                  )
                else if (slot.kind == 'course')
                  Text(
                    '课程安排来自门户课表',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  PlannerEvent? _findEvent(AppState s, CourseOccurrence o) {
    final iso = Semester.iso(o.date);
    for (final e in [...s.events, ...demoExams]) {
      if (e.name == o.slot.name &&
          e.dateIso == iso &&
          e.startMinutes == o.slot.startMinutes) {
        return e;
      }
    }
    return null;
  }

  Widget _detailRow(BuildContext context, IconData icon, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(k,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── 学期状态条 ────────────────────────────────────────────
class _SemesterBanner extends StatelessWidget {
  const _SemesterBanner({required this.week});

  final int week;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String text;
    IconData icon;
    Color bg, fg;
    if (week < 1) {
      icon = Icons.ac_unit;
      text = '学期尚未开始 · 第 1 周自 8 月 30 日起';
      bg = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
      fg = scheme.onSurfaceVariant;
    } else if (week > Semester.totalWeeks) {
      icon = Icons.ac_unit;
      text = '本学期已结束（共 ${Semester.totalWeeks} 周），寒假快乐';
      bg = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
      fg = scheme.onSurfaceVariant;
    } else if (Semester.isExamWeek(week)) {
      icon = Icons.fact_check;
      text = '考试周（第 $week 周）· 期末考试进行中';
      bg = const Color(0xFFB4345C).withValues(alpha: 0.12);
      fg = const Color(0xFFB4345C);
    } else {
      icon = Icons.school;
      text = '第 $week 教学周 / 共 ${Semester.totalWeeks} 周';
      bg = scheme.primaryContainer.withValues(alpha: 0.45);
      fg = scheme.onPrimaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 周切换头 ──────────────────────────────────────────────
class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({
    required this.weekNumber,
    required this.rangeText,
    required this.isCurrent,
    required this.onPrev,
    required this.onNext,
    required this.onBackToCurrent,
  });

  final int weekNumber;
  final String rangeText;
  final bool isCurrent;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onBackToCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isApple ? 10 : 8,
        vertical: isApple ? 6 : 4,
      ),
      child: Row(
        children: [
          isApple
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: onPrev,
                  child: const Icon(CupertinoIcons.chevron_left, size: 20),
                )
              : IconButton(
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一周',
                ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '第 $weekNumber 周',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  rangeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          isApple
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: onNext,
                  child: const Icon(CupertinoIcons.chevron_right, size: 20),
                )
              : IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一周',
                ),
          if (!isCurrent) ...[
            const SizedBox(width: 4),
            isApple
                ? CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: const Size(32, 28),
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    onPressed: onBackToCurrent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.calendar_today,
                            size: 13, color: scheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          '本周',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Tooltip(
                    message: '回到本周',
                    child: IconButton(
                      onPressed: onBackToCurrent,
                      icon: const Icon(Icons.today, size: 20),
                    ),
                  ),
          ],
        ],
      ),
    );

    if (isApple) {
      return IosGlassSurface(
        radius: 14,
        child: content,
      );
    }
    return content;
  }
}

// ── 课表视图模式栏（整周一屏 / 横向滑动）──────────────────
class _ScheduleModeBar extends StatelessWidget {
  const _ScheduleModeBar({
    required this.fitToScreen,
    required this.onToggle,
  });

  final bool fitToScreen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: fitToScreen
                      ? scheme.primary.withValues(alpha: 0.12)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: fitToScreen
                        ? scheme.primary.withValues(alpha: 0.35)
                        : scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      fitToScreen
                          ? Icons.fit_screen
                          : Icons.view_week_outlined,
                      size: 13,
                      color: fitToScreen
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fitToScreen ? '整周一屏' : '横向滑动',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: fitToScreen
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fitToScreen ? '一屏全览整周课程 · 点按看详情' : '左右滑动查看整周 · 点按看详情',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 节次网格（教务规范）──────────────────────────────────
class _Grid extends StatelessWidget {
  const _Grid({
    required this.days,
    required this.weekStart,
    required this.today,
    required this.isCurrentWeek,
    required this.onEventTap,
    this.fitToScreen = false,
    this.rowHeight = _SchedulePageState._rowH,
  });

  final List<List<CourseOccurrence>> days; // 周一..周日
  final DateTime weekStart;
  final DateTime today;
  final bool isCurrentWeek;
  final void Function(CourseOccurrence) onEventTap;
  final bool fitToScreen;
  final double rowHeight;

  /// 分钟 → 网格 Y 坐标（按节次行，用于“现在”指示线）。
  static double minuteToY(int minutes, double rowH) {
    final p = Semester.periodOf(minutes);
    final pairIdx = (p - 1) ~/ 2;
    final within = (p - 1) % 2;
    final s = Semester.periodStarts[p - 1];
    final e = Semester.periodEnds[p - 1];
    final frac = ((minutes - s) / (e - s)).clamp(0.0, 1.0);
    return pairIdx * rowH + (within + frac) * rowH / 2;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final double headerH = (fitToScreen ? 38.0 : 48.0) *
        MediaQuery.textScalerOf(context).scale(1);
    final contentH = rowHeight * 5;

    final gridContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PeriodColumn(
          weekStart: weekStart,
          fitToScreen: fitToScreen,
          rowHeight: rowHeight,
        ),
        for (var d = 0; d < 7; d++)
          _DayColumn(
            weekday: d + 1,
            date: weekStart.add(Duration(days: (d + 1) % 7)),
            occurrences: days[d],
            isToday: isCurrentWeek &&
                _sameDay(weekStart.add(Duration(days: (d + 1) % 7)), today),
            flex: fitToScreen ? (d >= 5 ? 75 : 100) : (d >= 5 ? 62 : 100),
            fitToScreen: fitToScreen,
            rowHeight: rowHeight,
            onEventTap: onEventTap,
          ),
      ],
    );

    Widget grid = isApple
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: IosGlassSurface(
              radius: Ds.rLg,
              child: gridContent,
            ),
          )
        : Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: gridContent,
          );

    if (isCurrentWeek) {
      final cur = today.hour * 60 + today.minute;
      if (cur >= Semester.periodStarts.first &&
          cur <= Semester.periodEnds.last) {
        grid = Stack(
          children: [
            grid,
            Positioned(
              left: fitToScreen ? 24 : 64,
              right: 10,
              top: headerH + minuteToY(cur, rowHeight),
              child: IgnorePointer(
                child: Container(
                  height: 1.6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.error,
                        scheme.error.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
    }
    return SizedBox(height: contentH + headerH + 28, child: grid);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _PeriodColumn extends StatelessWidget {
  const _PeriodColumn({
    required this.weekStart,
    this.fitToScreen = false,
    this.rowHeight = _SchedulePageState._rowH,
  });

  final DateTime weekStart;
  final bool fitToScreen;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: fitToScreen ? 24 : 64,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: fitToScreen ? 2 : 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${weekStart.month}月',
                  style: TextStyle(
                    fontSize: fitToScreen ? 9.5 : 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '',
                  style: TextStyle(
                    fontSize: fitToScreen ? 9.0 : 10,
                  ),
                ),
              ],
            ),
          ),
          for (var pair = 0; pair < 5; pair++)
            Expanded(
              child: fitToScreen
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${pair * 2 + 1}',
                            style: TextStyle(
                              fontSize: 9.0,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${pair * 2 + 2}',
                            style: TextStyle(
                              fontSize: 9.0,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '第${pair * 2 + 1}-${pair * 2 + 2}节',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          Semester.hm(Semester.periodStarts[pair * 2]),
                          style: TextStyle(
                            fontSize: 9.5,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          Semester.hm(Semester.periodStarts[pair * 2 + 1]),
                          style: TextStyle(
                            fontSize: 9.5,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.weekday,
    required this.date,
    required this.occurrences,
    required this.isToday,
    required this.flex,
    required this.onEventTap,
    this.fitToScreen = false,
    this.rowHeight = _SchedulePageState._rowH,
  });

  final int weekday;
  final DateTime date;
  final List<CourseOccurrence> occurrences;
  final bool isToday;
  final int flex;
  final void Function(CourseOccurrence) onEventTap;
  final bool fitToScreen;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final holiday = Semester.isHoliday(date);

    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: fitToScreen ? 2 : 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: isToday
                  ? BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fitToScreen
                            ? ['一', '二', '三', '四', '五', '六', '日'][weekday - 1]
                            : Fmt.weekNames[weekday - 1],
                        style: TextStyle(
                          fontSize: fitToScreen ? 10.5 : 11,
                          fontWeight:
                              isToday ? FontWeight.w800 : FontWeight.w600,
                          color: isToday
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (holiday && !fitToScreen) ...[
                        const SizedBox(width: 2),
                        Text('休',
                            style:
                                TextStyle(fontSize: 8, color: scheme.tertiary)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    fitToScreen ? '${date.day}' : '${date.month}/${date.day}',
                    style: TextStyle(
                      fontSize: fitToScreen ? 9.0 : 10,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // 大节分隔线（5 行）
                Positioned.fill(
                  child: Column(
                    children: [
                      for (var pair = 0; pair < 5; pair++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              border: Border(
                                top: pair == 0
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: scheme.outlineVariant
                                            .withValues(alpha: 0.35),
                                      ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (holiday && occurrences.isEmpty)
                  Positioned(
                    left: 2,
                    right: 2,
                    top: rowHeight * 0.3,
                    child: const Text('假期',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9.0, color: Colors.grey)),
                  ),
                for (final o in occurrences) _buildBlock(context, o),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, CourseOccurrence occ) {
    final slot = occ.slot;
    final tone = NeuColors.adaptiveTone(context, NeuColors.slotTone(slot));
    var sp = Semester.startPeriodOf(slot.startMinutes);
    var ep = Semester.endPeriodOf(slot.endMinutes);
    if (ep < sp) ep = sp;
    if (sp > 10) return const SizedBox.shrink();
    sp = sp.clamp(1, 10);
    ep = ep.clamp(1, 10);
    final top = ((sp - 1) * rowHeight) / 2;
    final h = ((ep - sp + 1) * rowHeight) / 2;
    final custom = slot.kind == 'custom';
    final exam = slot.kind == 'exam';
    final weekText = slot.weekStart > 0 && slot.weekEnd < 99
        ? (slot.weekStart == slot.weekEnd
            ? '${slot.weekStart}周'
            : '${slot.weekStart}-${slot.weekEnd}周')
        : '';
    final tall = h >= (fitToScreen ? 70 : 80);
    final isCompact = fitToScreen || h < 55;

    return Positioned(
      left: fitToScreen ? 1.5 : 4,
      right: fitToScreen ? 1.5 : 4,
      top: top + 1,
      height: (h - 2).clamp(16.0, double.infinity),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(fitToScreen ? 6 : 9),
          onTap: () => onEventTap(occ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: fitToScreen ? 2 : 4,
              vertical: fitToScreen ? 2 : 3,
            ),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: custom ? 0.10 : 0.18),
              borderRadius: BorderRadius.circular(fitToScreen ? 6 : 9),
              border: Border.all(
                color: tone.withValues(alpha: custom ? 0.7 : 0.6),
                width: custom ? 1.2 : 0.9,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((exam || custom) && !isCompact && h >= 65) ...[
                  Row(
                    children: [
                      Icon(exam ? Icons.fact_check : Icons.push_pin,
                          size: 9, color: tone),
                      const SizedBox(width: 2),
                      Text(exam ? '考试' : '日程',
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: tone)),
                    ],
                  ),
                  const SizedBox(height: 1),
                ],
                Flexible(
                  child: Text(
                    slot.name,
                    maxLines: h >= 50 ? (tall ? 3 : 2) : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fitToScreen ? 8.5 : 9.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ),
                if (tall && weekText.isNotEmpty && h >= 80)
                  Text(
                    weekText,
                    style: TextStyle(
                      fontSize: 8.0,
                      color: tone.withValues(alpha: 0.85),
                    ),
                  ),
                if (slot.room.isNotEmpty && h >= 48) ...[
                  const Spacer(),
                  Text(
                    slot.room,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fitToScreen ? 7.5 : 8.5,
                      color: tone.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 日期/时间选择磁贴 ─────────────────────────────────────
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: scheme.primary),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Own the fields until the sheet's exit animation finishes and it unmounts.
class _EventFormControllers extends StatefulWidget {
  const _EventFormControllers({required this.builder});
  final Widget Function(
      BuildContext, TextEditingController, TextEditingController) builder;
  @override
  State<_EventFormControllers> createState() => _EventFormControllersState();
}

class _EventFormControllersState extends State<_EventFormControllers> {
  final _name = TextEditingController();
  final _room = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _name, _room);
}
