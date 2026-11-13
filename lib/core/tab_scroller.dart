/// 底栏重复点击回顶：各页签注册自己的滚动控制器。
library;

import 'package:flutter/material.dart';

/// Tab destinations appear immediately; their lists need no staggered entrance.
/// Other routes can still opt into the standard entry animations.
class PortalTabContent extends InheritedWidget {
  const PortalTabContent({
    super.key,
    required this.animateEntrance,
    required super.child,
  });

  final bool animateEntrance;

  static bool animateOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PortalTabContent>()
          ?.animateEntrance ??
      true;

  @override
  bool updateShouldNotify(PortalTabContent oldWidget) =>
      animateEntrance != oldWidget.animateEntrance;
}

abstract final class TabScroller {
  static final List<ScrollController?> _controllers = List.filled(5, null);

  static void attach(int index, ScrollController controller) {
    _controllers[index] = controller;
  }

  static void detach(int index, ScrollController controller) {
    // 同一帧内可能先挂载新页面、再销毁旧页面，只注销当前控制器。
    if (index >= 0 &&
        index < _controllers.length &&
        identical(_controllers[index], controller)) {
      _controllers[index] = null;
    }
  }

  static void scrollToTop(int index, {bool animated = true}) {
    if (index < 0 || index >= _controllers.length) return;
    final c = _controllers[index];
    if (c != null && c.hasClients) {
      final top = c.position.minScrollExtent;
      if (!animated) {
        c.jumpTo(top);
        return;
      }
      c.animateTo(
        top,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }
}

/// Lets shortcuts select an existing tab and retain that tab's state.
class PortalNavigation extends InheritedWidget {
  const PortalNavigation({
    super.key,
    required this.select,
    this.bottomInset,
    required super.child,
  });
  final ValueChanged<int> select;

  /// Captured outside nested Scaffolds, which can consume viewPadding.
  final double? bottomInset;
  static PortalNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortalNavigation>();
  @override
  bool updateShouldNotify(PortalNavigation oldWidget) =>
      select != oldWidget.select || bottomInset != oldWidget.bottomInset;
}
