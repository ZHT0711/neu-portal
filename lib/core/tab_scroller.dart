/// 底栏双击回顶：各页签注册自己的滚动控制器。
/// 外壳检测「同一页签 400ms 内双击」后调用 [TabScroller.scrollToTop]。
library;

import 'package:flutter/material.dart';

abstract final class TabScroller {
  static final List<ScrollController?> _controllers = List.filled(5, null);

  static void attach(int index, ScrollController controller) {
    _controllers[index] = controller;
  }

  static void detach(int index) {
    if (index >= 0 && index < _controllers.length) _controllers[index] = null;
  }

  static void scrollToTop(int index) {
    final c = _controllers[index];
    if (c != null && c.hasClients) {
      c.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }
}

/// Lets shortcuts select an existing tab and retain that tab's state.
class PortalNavigation extends InheritedWidget {
  const PortalNavigation(
      {super.key, required this.select, required super.child});
  final ValueChanged<int> select;
  static PortalNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortalNavigation>();
  @override
  bool updateShouldNotify(PortalNavigation oldWidget) =>
      select != oldWidget.select;
}
