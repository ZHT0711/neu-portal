import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/app_state.dart';
import '../core/platform_style.dart';
import '../core/ios_glass.dart';
import '../core/links.dart';
import '../core/tab_scroller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'learning_page.dart';
import 'card_page.dart';

/// 服务大厅：智慧搜索（热词 + 本地过滤 + 智搜平台）+ 全部应用 + 专题服务。
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _queryCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  String _category = '全部';
  Timer? _searchDebounce;

  List<PortalApp>? _indexedAppsSource;
  List<String>? _indexedAppNames;
  List<String?>? _indexedAppDescriptions;
  List<PortalApp>? _categorizedAppsSource;
  List<String> _categories = const ['全部'];
  List<ServiceSection>? _indexedServicesSource;
  List<List<({ServiceEntry entry, String name})>> _indexedServices = [];

  void _indexCategories(List<PortalApp> apps) {
    if (identical(_categorizedAppsSource, apps)) return;

    final counts = <String, int>{};
    for (final app in apps) {
      if (app.category.isNotEmpty) {
        counts[app.category] = (counts[app.category] ?? 0) + 1;
      }
    }
    final categories = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    _categories = ['全部', ...categories];
    _categorizedAppsSource = apps;
  }

  List<PortalApp> _searchApps(List<PortalApp> apps, String query) {
    final cached = identical(_indexedAppsSource, apps);
    final names = cached
        ? _indexedAppNames!
        : List<String>.filled(apps.length, '');
    final descriptions = cached
        ? _indexedAppDescriptions!
        : List<String?>.filled(apps.length, null);
    final matches = <PortalApp>[];

    if (cached) {
      for (var i = 0; i < apps.length; i++) {
        final app = apps[i];
        if (_category != '全部' && app.category != _category) continue;
        if (names[i].contains(query)) {
          matches.add(app);
          continue;
        }
        final description = descriptions[i] ??= app.desc.toLowerCase();
        if (description.contains(query)) matches.add(app);
      }
    } else {
      for (var i = 0; i < apps.length; i++) {
        final app = apps[i];
        final name = app.name.toLowerCase();
        names[i] = name;
        if (_category != '全部' && app.category != _category) continue;
        if (name.contains(query)) {
          matches.add(app);
          continue;
        }
        final description = app.desc.toLowerCase();
        descriptions[i] = description;
        if (description.contains(query)) matches.add(app);
      }
      _indexedAppNames = names;
      _indexedAppDescriptions = descriptions;
      _indexedAppsSource = apps;
    }
    return matches;
  }

  void _indexServices(List<ServiceSection> sections) {
    if (identical(_indexedServicesSource, sections)) return;
    _indexedServices = [
      for (final section in sections)
        [
          for (final entry in section.entries)
            (entry: entry, name: entry.name.toLowerCase()),
        ],
    ];
    _indexedServicesSource = sections;
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _query = value);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  void initState() {
    super.initState();
    TabScroller.attach(2, _scroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    TabScroller.detach(2, _scroll);
    _queryCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    _indexCategories(s.apps);
    final q = _query.trim().toLowerCase();
    final hasQuery = q.isNotEmpty;
    late final List<PortalApp> apps;
    if (!hasQuery) {
      if (_category == '全部') {
        apps = s.apps;
      } else {
        apps = [
          for (final app in s.apps)
            if (app.category == _category) app,
        ];
      }
      if (!identical(_indexedAppsSource, s.apps)) {
        _indexedAppsSource = null;
        _indexedAppNames = null;
        _indexedAppDescriptions = null;
      }
    } else {
      apps = _searchApps(s.apps, q);
    }

    late final List<ServiceSection> sections;
    if (!hasQuery) {
      sections = s.services;
      if (!identical(_indexedServicesSource, s.services)) {
        _indexedServicesSource = null;
        _indexedServices = [];
      }
    } else {
      _indexServices(s.services);
      final matches = <ServiceSection>[];
      for (var i = 0; i < s.services.length; i++) {
        final section = s.services[i];
        final entries = <ServiceEntry>[];
        for (final indexed in _indexedServices[i]) {
          if (indexed.name.contains(q)) entries.add(indexed.entry);
        }
        if (entries.isNotEmpty) {
          matches.add(ServiceSection(section.name, entries));
        }
      }
      sections = matches;
    }
    final scheme = Theme.of(context).colorScheme;
    final noLocalMatch = apps.isEmpty && sections.isEmpty;

    return Scaffold(
      appBar: isApple ? null : const PageAppBar(title: '服务'),
      body: CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (isApple)
            CupertinoSliverNavigationBar(
              backgroundColor: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context)
                  .withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.80
                        : 0.72,
                  ),
              border: Border(
                bottom: BorderSide(
                  color: IosColors.separator(
                    Theme.of(context).brightness == Brightness.dark,
                  ).withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              largeTitle: const Text('服务'),
              transitionBetweenRoutes: false,
            ),

          if (q.isEmpty)
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(child: Column(children: [
                Card(child: ListTile(leading: const Icon(Icons.assignment_outlined),
                  title: const Text('学习任务'), subtitle: const Text('CG · 慕课与 SPOC · 学习通任务点'),
                  trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LearningPage())))),
                Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('校园卡'), subtitle: const Text('主钱包余额 · 月流水查询'),
                  trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CardPage())))),
              ]))),

          // ── 搜索框 ──
          SliverPadding(
            key: const ValueKey('services-search'),
            padding: EdgeInsets.fromLTRB(16, isApple ? 12 : 6, 16, 0),
            sliver: SliverToBoxAdapter(
              child: AdaptiveSearchField(
                controller: _queryCtrl,
                onChanged: _onSearchChanged,
              ),
            ),
          ),

          // ── 热门搜索（门户真实热词）──
          if (q.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _HotSearchRow(
                  hots: s.hotSearches,
                  onPick: (kw) {
                    _searchDebounce?.cancel();
                    setState(() {
                      _queryCtrl.text = kw;
                      _query = kw;
                    });
                  },
                ),
              ),
            ),

          // ── 分类筛选 ──
          SliverToBoxAdapter(
            child: _CategoryChips(
              categories: _categories,
              selected: _category,
              onSelected: (c) => setState(() => _category = c),
            ),
          ),

          // ── 智慧搜索入口：有词就显示；本地无匹配时置顶 ──
          if (q.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, noLocalMatch ? 14 : 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _SmartSearchCard(keyword: _query.trim()),
              ),
            ),

          // ── 本地无匹配提示 ──
          if (noLocalMatch)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Panel(
                  child: EmptyHint(
                    '本地没有匹配的应用，试试上方智慧搜索',
                    icon: Icons.search_off,
                  ),
                ),
              ),
            ),

          // ── 应用网格 ──
          if (apps.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  q.isEmpty && _category == '全部'
                      ? '全部应用（${apps.length}）'
                      : '应用（${apps.length}）',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _SliverPanelGrid(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 8,
              ),
              columnWidth: 96,
              maxColumns: 8,
              minColumns: 2,
              itemExtent: 88 + MediaQuery.textScalerOf(context).scale(24),
              itemCount: apps.length,
              itemBuilder: (context, i) {
                final a = apps[i];
                return AppTile(
                  name: a.name,
                  iconUrl: a.iconUrl,
                  dense: true,
                  onTap: () => AppLinks.openApp(context, a),
                );
              },
            ),
          ],

          // ── 专题服务 ──
          for (final sec in sections) ...[
            SliverToBoxAdapter(child: SectionHeader(sec.name)),
            _SliverPanelGrid(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              contentPadding: const EdgeInsets.all(10),
              columnWidth: 220,
              maxColumns: 4,
              itemExtent: 52 + MediaQuery.textScalerOf(context).scale(12),
              spacing: 8,
              itemCount: sec.entries.length,
              itemBuilder: (context, i) {
                final e = sec.entries[i];
                return InkWell(
                  onTap: () => openPortalLink(context, e.url, title: e.name),
                  borderRadius: BorderRadius.circular(13),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (e.desc.isNotEmpty)
                          Text(
                            e.desc,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],

          SliverToBoxAdapter(
            child: SizedBox(height: portalBottomInset(context)),
          ),
        ],
      ),
    );
  }
}

/// 保留分组卡片外观，用原生 sliver 只创建视口及缓存区内的网格项。
class _SliverPanelGrid extends StatelessWidget {
  const _SliverPanelGrid({
    required this.padding,
    required this.contentPadding,
    required this.columnWidth,
    required this.maxColumns,
    this.minColumns = 1,
    required this.itemExtent,
    this.spacing = 0,
    required this.itemCount,
    required this.itemBuilder,
  });

  final EdgeInsets padding;
  final EdgeInsets contentPadding;
  final double columnWidth;
  final int maxColumns;
  final int minColumns;
  final double itemExtent;
  final double spacing;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SliverPadding(
      padding: padding,
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: isApple
              ? IosColors.secondaryGroupedBackground(dark)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(isApple ? Ds.rMd : Ds.rLg),
          border: isApple
              ? Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0x14000000),
                  width: 0.6,
                )
              : null,
        ),
        sliver: SliverPadding(
          padding: contentPadding,
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (constraints.crossAxisExtent / columnWidth)
                    .floor()
                    .clamp(minColumns, maxColumns),
                mainAxisExtent: itemExtent,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: itemCount,
              itemBuilder: (context, i) => Material(
                type: MaterialType.transparency,
                child: itemBuilder(context, i),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 门户热搜词（frontend/search/hot 实时数据）。
class _HotSearchRow extends StatelessWidget {
  const _HotSearchRow({required this.hots, required this.onPick});

  final List<String> hots;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (hots.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(
                Icons.local_fire_department,
                size: 15,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 5),
              Text(
                '热门搜索',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 28 + MediaQuery.textScalerOf(context).scale(24),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hots.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final kw = hots[i];
              return InkWell(
                onTap: () => onPick(kw),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: i == 0
                        ? scheme.tertiaryContainer.withValues(alpha: 0.7)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i < 3)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: scheme.tertiary,
                            ),
                          ),
                        ),
                      Text(
                        kw,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 智慧搜索入口：跳转门户智搜平台（SSO 免登录，全校统一搜索）。
class _SmartSearchCard extends StatelessWidget {
  const _SmartSearchCard({required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, scheme.tertiary, 0.5)!,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.travel_explore, color: Colors.white),
      ),
      title: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            const TextSpan(text: '在智慧搜索中查 '),
            TextSpan(
              text: '「$keyword」',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
      subtitle: const Text(
        '全校系统 · 通知 · 服务一键直达',
        style: TextStyle(fontSize: 11.5),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => AppLinks.open(
        context,
        'https://so.neu.edu.cn/#/accessLogin?searchWord=${Uri.encodeComponent(keyword)}',
        title: '智慧搜索',
      ),
    );

    if (isApple) {
      return IosGlassSurface(
        radius: Ds.rMd,
        child: Material(color: Colors.transparent, child: tile),
      );
    }

    return Card(child: tile);
  }
}

/// 分类筛选条。
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40 + MediaQuery.textScalerOf(context).scale(20),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = categories[i];
          final active = category == selected;
          if (isApple) {
            return Semantics(
              selected: active,
              child: CupertinoButton(
                color: active ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () => onSelected(category),
                child: Text(
                  category,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: active ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            );
          }
          return ChoiceChip(
            selected: active,
            label: Text(category),
            showCheckmark: false,
            onSelected: (_) => onSelected(category),
          );
        },
      ),
    );
  }
}
