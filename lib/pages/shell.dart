import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
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

    final navBar = NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) {
        if (i != _index) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        }
      },
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
      onDestinationSelected: (i) {
        if (i != _index) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        }
      },
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
      bottomNavigationBar: wide ? null : navBar,
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
