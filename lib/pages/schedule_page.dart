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
  final _scroll = ScrollController();
  final Map<String, List<CourseOccurrence>> _remoteCache = {};
  bool _fetching = false;
  bool _fetchFailed = false;

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
  void dispose() {
    TabScroller.detach(1);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _maybeFetch() async {
    final s = AppScope.of(context);
    if (s.mode != SessionMode.live) return;
    final key = Semester.iso(_weekStart);
    if (_remoteCache.containsKey(key) || _fetching) return;
    setState(() => _fetching = true);
    try {
      final occs = await s.fetchWeek(_weekStart);
      if (occs.isNotEmpty) _remoteCache[key] = occs;
      _fetchFailed = false;
    } catch (_) {
      _fetchFailed = true;
    } finally {
      if (mounted) setState(() => _fetching = false);
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

    return Scaffold(
      appBar: PageAppBar(
        title: '课表',
        actions: [
          if (isApple)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => _showEventForm(context),
              child: Semantics(
                  label: '添加日程',
                  button: true,
                  child: const Icon(CupertinoIcons.add)),
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
      floatingActionButton: isApple
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showEventForm(context),
              icon: const Icon(Icons.add),
              label: const Text('添加日程'),
            ),
      body: Column(
        children: [
          _WeekSwitcher(
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
          ),
          _SemesterBanner(week: week),
          if (MediaQuery.sizeOf(context).width <
              680 * MediaQuery.textScalerOf(context).scale(1))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('左右滑动查看整周 · 点按课程查看详情',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: portalBottomInset(context)),
              child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
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
                            onEventTap: (occ) => _showDetail(context, occ),
                          ),
                        ),
                      )),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '第 $weekNumber 周',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  rangeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
          ),
          if (!isCurrent)
            Tooltip(
              message: '回到本周',
              child: IconButton(
                onPressed: onBackToCurrent,
                icon: const Icon(Icons.today, size: 20),
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
  });

  final List<List<CourseOccurrence>> days; // 周一..周日
  final DateTime weekStart;
  final DateTime today;
  final bool isCurrentWeek;
  final void Function(CourseOccurrence) onEventTap;

  static const double _rowH = _SchedulePageState._rowH;

  /// 分钟 → 网格 Y 坐标（按节次行，用于“现在”指示线）。
  static double minuteToY(int minutes) {
    final p = Semester.periodOf(minutes);
    final pairIdx = (p - 1) ~/ 2;
    final within = (p - 1) % 2;
    final s = Semester.periodStarts[p - 1];
    final e = Semester.periodEnds[p - 1];
    final frac = ((minutes - s) / (e - s)).clamp(0.0, 1.0);
    return pairIdx * _rowH + (within + frac) * _rowH / 2;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contentH = _rowH * 5;

    final gridContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PeriodColumn(),
        for (var d = 0; d < 7; d++)
          _DayColumn(
            weekday: d + 1,
            date: weekStart.add(Duration(days: (d + 1) % 7)),
            occurrences: days[d],
            isToday: isCurrentWeek &&
                _sameDay(weekStart.add(Duration(days: (d + 1) % 7)), today),
            flex: d >= 5 ? 62 : 100,
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
              left: 64,
              right: 10,
              top: 52 + minuteToY(cur),
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
    return SizedBox(height: contentH + 52, child: grid);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _PeriodColumn extends StatelessWidget {
  const _PeriodColumn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          for (var pair = 0; pair < 5; pair++)
            SizedBox(
              height: _Grid._rowH,
              child: Column(
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
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
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
  });

  final int weekday;
  final DateTime date;
  final List<CourseOccurrence> occurrences;
  final bool isToday;
  final int flex;
  final void Function(CourseOccurrence) onEventTap;

  static const double _rowH = _SchedulePageState._rowH;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final holiday = Semester.isHoliday(date);

    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: isToday
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  )
                : null,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Fmt.weekNames[weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                        color:
                            isToday ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (holiday) ...[
                      const SizedBox(width: 3),
                      Text('休',
                          style:
                              TextStyle(fontSize: 8.5, color: scheme.tertiary)),
                    ],
                  ],
                ),
                Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isToday
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
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
                            margin: const EdgeInsets.symmetric(horizontal: 3),
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
                  const Positioned(
                    left: 4,
                    right: 4,
                    top: 40,
                    child: Text('假期',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9.5, color: Colors.grey)),
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
    final top = ((sp - 1) * _rowH) / 2;
    final h = ((ep - sp + 1) * _rowH) / 2;
    final custom = slot.kind == 'custom';
    final exam = slot.kind == 'exam';
    final weekText = slot.weekStart > 0 && slot.weekEnd < 99
        ? (slot.weekStart == slot.weekEnd
            ? '${slot.weekStart}周'
            : '${slot.weekStart}-${slot.weekEnd}周')
        : '';
    final tall = h >= 80;
    return Positioned(
      left: 4,
      right: 4,
      top: top,
      height: h,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => onEventTap(occ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: custom ? 0.10 : 0.16),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: tone.withValues(alpha: custom ? 0.7 : 0.55),
                width: custom ? 1.2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (exam || custom)
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
                if (exam || custom) const SizedBox(height: 1),
                Text(
                  slot.name,
                  maxLines: tall ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
                if (tall && weekText.isNotEmpty)
                  Text(
                    weekText,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: tone.withValues(alpha: 0.85),
                    ),
                  ),
                const Spacer(),
                Text(
                  slot.room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: tone.withValues(alpha: 0.9),
                  ),
                ),
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
