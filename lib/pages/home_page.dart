import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/links.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'schedule_page.dart';
import 'services_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final now = DateTime.now();
    final today = s.todayAgenda();
    final next = s.nextAgenda();

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await s.refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            pinned: false,
            expandedHeight: 152,
            toolbarHeight: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(
                name: s.user.name,
                sid: s.user.sid,
                avatarUrl: s.user.avatarUrl,
                greeting: Fmt.greeting(now),
                dateText: Fmt.full(now),
                isDemo: s.mode == SessionMode.demo,
                ecodeUrl: s.ecodeEntryUrl,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _SearchCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ServicesPage()),
                      ),
                    ),
                  ),
                  if (next != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: StaggerIn(
                        index: 1,
                        child: _NextCourseBanner(occ: next),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: StaggerIn(index: 2, child: _StatsStrip(s: s)),
                  ),
                  SectionHeader(
                    '今日课程',
                    action: '完整课表',
                    onAction: () => _openSchedule(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child:
                        StaggerIn(index: 3, child: _TodaySchedule(courses: today)),
                  ),
                  SectionHeader(
                      '常用应用',
                      action: '服务大厅',
                      onAction: () => _openServices(context)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StaggerIn(index: 4, child: _AppsPager(apps: s.apps)),
                  ),
                  const SectionHeader('办事动态'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StaggerIn(index: 5, child: _TodoRail(todos: s.todos)),
                  ),
                  const SectionHeader('校园资讯'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StaggerIn(
                        index: 6, child: _NewsList(news: s.news.take(6).toList())),
                  ),
                  const SizedBox(height: 34),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _openSchedule(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SchedulePage()));
  }

  static void _openServices(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ServicesPage()));
  }
}

// ── 顶部问候区 ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.sid,
    required this.avatarUrl,
    required this.greeting,
    required this.dateText,
    this.isDemo = false,
    this.ecodeUrl = '',
  });

  final String name;
  final String sid;
  final String avatarUrl;
  final String greeting;
  final String dateText;
  final bool isDemo;
  final String ecodeUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.7, 1],
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.45)!,
            Color.lerp(scheme.primary, scheme.tertiary, 0.7)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55), width: 1.6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15.5),
                  child: Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.18),
                      alignment: Alignment.center,
                      child: Text(
                        name.isNotEmpty ? name.characters.first : '同',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting，$name',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$sid · 未来技术学院',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(Icons.event_available,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.85)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            dateText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isDemo) ...[
                          const SizedBox(width: 9),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                '离线演示',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white, fontSize: 10.5),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  AppLinks.open(context, ecodeUrl, title: 'e码通');
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2, color: Colors.white, size: 27),
                      SizedBox(height: 1),
                      Text('e码通',
                          style: TextStyle(
                              color: Colors.white, fontSize: 8.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 搜索 ─────────────────────────────────────────────────
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Material(
      color: dark ? scheme.surfaceContainerLow : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: dark ? 0 : 2,
      shadowColor: scheme.primary.withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Text('搜索应用与服务…',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_forward,
                    size: 13, color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 下一节课 ─────────────────────────────────────────────
class _NextCourseBanner extends StatelessWidget {
  const _NextCourseBanner({required this.occ});

  final CourseOccurrence occ;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = NeuColors.slotTone(occ.slot);
    final now = DateTime.now();
    final cur = now.hour * 60 + now.minute;
    final ongoing = cur >= occ.slot.startMinutes && cur < occ.slot.endMinutes;
    final kindLabel = occ.slot.kind == 'exam'
        ? '即将开考'
        : occ.slot.kind == 'custom'
            ? '接下来的日程'
            : (ongoing ? '正在上课' : '下一节课');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [tone.withValues(alpha: 0.2), tone.withValues(alpha: 0.08)],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                occ.slot.kind == 'exam'
                    ? Icons.fact_check
                    : occ.slot.kind == 'custom'
                        ? Icons.push_pin
                        : (ongoing ? Icons.play_circle : Icons.upcoming),
                color: tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kindLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tone,
                    ),
                  ),
                  Text(
                    '${occ.slot.name} · ${occ.slot.room}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Text(
              occ.slot.timeText,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 数据条 ───────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.s});

  final AppState s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icons = [
      Icons.forum_outlined,
      Icons.mark_email_unread_outlined,
      Icons.credit_card,
      Icons.wifi,
    ];
    final tones = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primary,
    ];
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          for (var i = 0; i < s.dataCards.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 34, color: scheme.outlineVariant.withValues(alpha: 0.6)),
            Expanded(
              child: Column(
                children: [
                  Icon(icons[i % icons.length], size: 17, color: tones[i % tones.length]),
                  const SizedBox(height: 6),
                  CountUpText(
                    s.dataCards[i].value,
                    suffix: s.dataCards[i].unit,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.dataCards[i].name,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 今日课程时间轴 ────────────────────────────────────────
class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.courses});

  final List<CourseOccurrence> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const Panel(
        child: EmptyHint('今天没有课，好好休息 ☕', icon: Icons.self_improvement),
      );
    }
    final now = DateTime.now();
    final cur = now.hour * 60 + now.minute;
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < courses.length; i++)
            _CourseRow(
              occ: courses[i],
              first: i == 0,
              ongoing:
                  cur >= courses[i].slot.startMinutes &&
                      cur < courses[i].slot.endMinutes,
            ),
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.occ,
    required this.first,
    required this.ongoing,
  });

  final CourseOccurrence occ;
  final bool first;
  final bool ongoing;

  @override
  Widget build(BuildContext context) {
    final tone = NeuColors.slotTone(occ.slot);
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = occ.slot.kind == 'exam' ? '考试' : occ.slot.kind == 'custom' ? '日程' : null;
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _hm(occ.slot.startMinutes),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: ongoing ? tone : scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _hm(occ.slot.endMinutes),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: tone,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: scheme.surfaceContainerLow, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: tone.withValues(alpha: 0.4), blurRadius: 6),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: 2.4,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: first ? 8 : 6, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          occ.slot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                      ),
                      if (kindLabel != null) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(kindLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: tone)),
                        ),
                      ] else if (ongoing) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('进行中',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: tone)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.place, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        occ.slot.room,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

// ── 常用应用分页 ──────────────────────────────────────────
class _AppsPager extends StatefulWidget {
  const _AppsPager({required this.apps});

  final List<PortalApp> apps;

  @override
  State<_AppsPager> createState() => _AppsPagerState();
}

class _AppsPagerState extends State<_AppsPager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final list = widget.apps.take(16).toList();
    final pages = <List<PortalApp>>[
      list.sublist(0, list.length >= 8 ? 8 : list.length),
      if (list.length > 8) list.sublist(8),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: SizedBox(
            height: 96,
            child: PageView.builder(
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, pi) {
                final chunk = pages[pi];
                return Row(
                  children: [
                    for (final a in chunk)
                      Expanded(
                        child: AppTile(
                          name: a.name,
                          iconUrl: a.iconUrl,
                          onTap: () =>
                              AppLinks.openApp(context, a),
                        ),
                      ),
                    for (var i = chunk.length; i < 8; i++)
                      const Expanded(child: SizedBox()),
                  ],
                );
              },
            ),
          ),
        ),
        if (pages.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  width: _page == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? scheme.primary
                        : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ── 办事动态横滑卡 ────────────────────────────────────────
class _TodoRail extends StatelessWidget {
  const _TodoRail({required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) {
      return const Panel(child: EmptyHint('暂无待办事项', icon: Icons.task_alt));
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: todos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final t = todos[i];
          final tone = NeuColors.avatarColor(t.title);
          final done = t.percent >= 100;
          return Panel(
            color: Theme.of(context).colorScheme.brightness == Brightness.light
                ? Colors.white
                : Theme.of(context).colorScheme.surfaceContainerLow,
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: t.url.isEmpty
                  ? null
                  : () => openPortalLink(context, t.url, title: t.title),
              child: Container(
                width: 232,
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            done ? Icons.task_alt : Icons.hourglass_top,
                            size: 15,
                            color: tone,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${t.percent}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: tone,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${t.time} · ${t.node}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 校园资讯 ─────────────────────────────────────────────
class _NewsList extends StatelessWidget {
  const _NewsList({required this.news});

  final List<NewsItem> news;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Column(
        children: [
          for (final n in news)
            InkWell(
              onTap: () => openPortalLink(context, n.url, title: n.title),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (n.picUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 46,
                          child: Image.network(
                            n.picUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _dateBadge(n, scheme),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                    ] else ...[
                      _dateBadge(n, scheme),
                      const SizedBox(width: 11),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${n.category} · ${Fmt.isoToCn(n.date)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateBadge(NewsItem n, ColorScheme scheme) {
    final parts = n.date.split('-');
    final month = parts.length >= 2 ? '${int.tryParse(parts[1]) ?? ''}月' : '';
    final day = parts.length >= 3
        ? (int.tryParse(parts[2]) ?? 0).toString().padLeft(2, '0')
        : '';
    return Container(
      width: 44,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onPrimaryContainer,
              height: 1.05,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            month,
            style: TextStyle(
              fontSize: 9.5,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
