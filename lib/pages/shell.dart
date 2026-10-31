import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/platform_style.dart' show isApple, GlassContainer, TabBarItem, hapticSelect;
import '../core/tab_scroller.dart';
import '../core/theme.dart';
import 'grades_page.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'schedule_page.dart';
import 'services_page.dart';

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _index = 0;
  DateTime? _lastTapAt;
  int? _lastTapIndex;

  /// 同一页签 400ms 内再次点击 → 回顶。
  void _select(int i) {
    final now = DateTime.now();
    final doubleTap = _lastTapIndex == i &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < const Duration(milliseconds: 400);
    _lastTapAt = now;
    _lastTapIndex = i;
    if (_index == i && doubleTap) {
      hapticSelect();
      TabScroller.scrollToTop(i);
      return;
    }
    if (_index != i) {
      hapticSelect();
      setState(() => _index = i);
    }
  }

  static const _pages = <Widget>[
    HomePage(),
    SchedulePage(),
    ServicesPage(),
    GradesPage(),
    ProfilePage(),
  ];

  static const _titles = ['首页', '课表', '服务', '成绩', '我的'];

  static const _icons = [
    Icons.space_dashboard_outlined,
    Icons.calendar_month_outlined,
    Icons.widgets_outlined,
    Icons.leaderboard_outlined,
    Icons.person_outline,
  ];

  static const _selectedIcons = [
    Icons.space_dashboard,
    Icons.calendar_month,
    Icons.widgets,
    Icons.leaderboard,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    final navBar = NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _select,
      destinations: [
        for (var i = 0; i < _titles.length; i++)
          NavigationDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_selectedIcons[i]),
            label: _titles[i],
          ),
      ],
    );

    final rail = NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: _select,
      extended: MediaQuery.sizeOf(context).width >= 1200,
      minExtendedWidth: 150,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.tertiary,
                  ],
                ),
              ),
              child: const Center(
                child: Text(
                  '门',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      labelType: NavigationRailLabelType.none,
      destinations: [
        for (var i = 0; i < _titles.length; i++)
          NavigationRailDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_selectedIcons[i]),
            label: Text(_titles[i]),
          ),
      ],
    );


    // iOS：悬浮液态玻璃标签栏（内容从其下方滚过）
    final Widget? bottomBar;
    if (wide) {
      bottomBar = null;
    } else if (isApple) {
      final dark = scheme.brightness == Brightness.dark;
      bottomBar = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: GlassContainer(
            dark: dark,
            borderRadius: BorderRadius.circular(Ds.full),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  for (var i = 0; i < _titles.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(i),
                        child: TabBarItem(
                          icon: _icons[i],
                          activeIcon: _selectedIcons[i],
                          label: _titles[i],
                          active: _index == i,
                          color: _index == i
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
  } else {
    bottomBar = navBar;
  }

    final body = Scaffold(
      appBar: wide
          ? AppBar(
              title: Text(_titles[_index]),
              actions: [
                if (s.mode == SessionMode.demo)
                  const _DemoBadge(),
                const SizedBox(width: 12),
              ],
            )
          : null,
      extendBody: !wide && isApple,
      body: Row(
        children: [
          if (wide) rail,
          Expanded(
            child: _FadeIndexedStack(
              index: _index,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );

    return body;
  }
}

/// IndexedStack + 渐隐渐现，切页不丢状态又带过渡。
class _FadeIndexedStack extends StatelessWidget {
  const _FadeIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < children.length; i++)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: children[i],
          ),
      ],
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.offline_bolt, size: 16, color: scheme.tertiary),
      label: const Text('离线演示', style: TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.tertiaryContainer,
      labelStyle: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
    );
  }
}
