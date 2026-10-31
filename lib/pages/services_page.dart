import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/links.dart';
import '../core/tab_scroller.dart';
import '../core/models.dart';
import '../widgets/common.dart';

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

  @override
  void initState() {
    super.initState();
    TabScroller.attach(2, _scroll);
  }

  @override
  void dispose() {
    TabScroller.detach(2);
    _queryCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    final byCate = _category == '全部'
        ? s.apps
        : s.apps.where((a) => a.category == _category).toList();
    final apps = q.isEmpty
        ? byCate
        : byCate
            .where((a) =>
                a.name.toLowerCase().contains(q) ||
                a.desc.toLowerCase().contains(q))
            .toList();
    final sections = q.isEmpty
        ? s.services
        : s.services
            .map((sec) => ServiceSection(
                sec.name,
                sec.entries
                    .where((e) => e.name.toLowerCase().contains(q))
                    .toList()))
            .where((sec) => sec.entries.isNotEmpty)
            .toList();
    final scheme = Theme.of(context).colorScheme;
    final noLocalMatch = apps.isEmpty && sections.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('服务')),
      body: CustomScrollView(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 搜索框 ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Material(
                color: scheme.brightness == Brightness.light
                    ? Colors.white
                    : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                elevation: scheme.brightness == Brightness.light ? 2 : 0,
                shadowColor: scheme.primary.withValues(alpha: 0.12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _queryCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: '搜索应用、服务，如「成绩」「缴费」',
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: scheme.primary),
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _queryCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ),
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
                  onPick: (kw) => setState(() {
                    _queryCtrl.text = kw;
                    _query = kw;
                  }),
                ),
              ),
            ),

          // ── 分类筛选 ──
          SliverToBoxAdapter(
            child: _CategoryChips(
              categories: _categoriesOf(s.apps),
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Panel(
                  child: const EmptyHint('本地没有匹配的应用，试试上方智慧搜索',
                      icon: Icons.search_off),
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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Panel(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  child: LayoutBuilder(builder: (ctx, box) {
                    final cols = (box.maxWidth / 96).floor().clamp(2, 8);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: 0.94,
                      ),
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
                    );
                  }),
                ),
              ),
            ),
          ],

          // ── 专题服务 ──
          for (final sec in sections) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 2),
              sliver: SliverToBoxAdapter(child: SectionHeader(sec.name)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Panel(
                  padding: const EdgeInsets.all(10),
                  child: LayoutBuilder(builder: (ctx2, box2) {
                    final cols2 = (box2.maxWidth / 220).floor().clamp(1, 4);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols2,
                        mainAxisExtent: 46,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: sec.entries.length,
                      itemBuilder: (context, i) {
                        final e = sec.entries[i];
                        return InkWell(
                          onTap: () =>
                              openPortalLink(context, e.url, title: e.name),
                          borderRadius: BorderRadius.circular(13),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.link_rounded,
                                    size: 16, color: scheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (e.desc.isNotEmpty)
                                  Text(e.desc,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.tertiary)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 34)),
        ],
      ),
    );
  }
}

List<String> _categoriesOf(List<PortalApp> apps) {
  final counts = <String, int>{};
  for (final a in apps) {
    if (a.category.isNotEmpty) {
      counts[a.category] = (counts[a.category] ?? 0) + 1;
    }
  }
  final cats = counts.keys.toList()
    ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  return ['全部', ...cats];
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
              Icon(Icons.local_fire_department,
                  size: 15, color: scheme.tertiary),
              const SizedBox(width: 5),
              Text('热门搜索',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final kw = hots[i];
              return InkWell(
                onTap: () => onPick(kw),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: i == 0
                        ? scheme.tertiaryContainer.withValues(alpha: 0.7)
                        : scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
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
                                color: scheme.tertiary),
                          ),
                        ),
                      Text(kw,
                          style:
                              TextStyle(fontSize: 12.5, color: scheme.onSurface)),
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
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              scheme.primary,
              Color.lerp(scheme.primary, scheme.tertiary, 0.5)!,
            ]),
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
                      fontWeight: FontWeight.w800, color: scheme.primary)),
            ],
          ),
        ),
        subtitle: const Text('全校系统 · 通知 · 服务一键直达',
            style: TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AppLinks.open(
          context,
          'https://so.neu.edu.cn/#/accessLogin?searchWord=' +
              Uri.encodeComponent(keyword),
          title: '智慧搜索',
        ),
      ),
    );
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
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final on = c == selected;
          return InkWell(
            onTap: () => onSelected(c),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: on
                    ? scheme.primary
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
