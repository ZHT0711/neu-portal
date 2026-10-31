import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/platform_style.dart';
import '../core/ios_glass.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../core/tab_scroller.dart';
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

  static const _appleIcons = [
    CupertinoIcons.house,
    CupertinoIcons.calendar,
    CupertinoIcons.square_grid_2x2,
    CupertinoIcons.chart_bar,
    CupertinoIcons.person,
  ];
  static const _appleSelectedIcons = [
    CupertinoIcons.house_fill,
    CupertinoIcons.calendar,
    CupertinoIcons.square_grid_2x2_fill,
    CupertinoIcons.chart_bar_fill,
    CupertinoIcons.person_fill,
  ];

  static const _appleSymbols = [
    'house',
    'calendar',
    'square.grid.2x2',
    'chart.bar',
    'person'
  ];
  static const _appleSelectedSymbols = [
    'house.fill',
    'calendar',
    'square.grid.2x2.fill',
    'chart.bar.fill',
    'person.fill'
  ];

  @override
  Widget build(BuildContext context) {
    final wide = !isApple && MediaQuery.sizeOf(context).width >= 900;

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
      labelType: MediaQuery.sizeOf(context).width >= 1200
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (var i = 0; i < _titles.length; i++)
          NavigationRailDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_selectedIcons[i]),
            label: Text(_titles[i]),
          ),
      ],
    );

    final Widget? bottomBar = wide
        ? null
        : isApple
            ? IosLiquidTabBar(
                index: _index,
                onTap: _select,
                items: [
                  for (var i = 0; i < _titles.length; i++)
                    LiquidGlassBarItem(
                      icon: _appleIcons[i],
                      selectedIcon: _appleSelectedIcons[i],
                      sfSymbol: _appleSymbols[i],
                      selectedSfSymbol: _appleSelectedSymbols[i],
                      label: _titles[i],
                    )
                ],
              )
            : navBar;

    final body = Scaffold(
      extendBody: isApple,
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

    return PortalNavigation(select: _select, child: body);
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
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: TickerMode(enabled: i == index, child: children[i]),
          ),
      ],
    );
  }
}
