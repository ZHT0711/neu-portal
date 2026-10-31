/// Native iOS Liquid Glass, with a readable Flutter fallback for previews.
library;

import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import 'platform_style.dart';

class IosGlassEnvironment extends StatefulWidget {
  const IosGlassEnvironment({super.key, required this.child});
  final Widget child;
  @override
  State<IosGlassEnvironment> createState() => _IosGlassEnvironmentState();
}

class _IosGlassEnvironmentState extends State<IosGlassEnvironment> {
  late final Future<LiquidGlassCapabilities> _capabilities = _probe();
  Future<LiquidGlassCapabilities> _probe() async {
    if (kIsWeb || !isApple) {
      return LiquidGlassCapabilities.none;
    }
    try {
      return await LiquidGlass.capabilities();
    } on PlatformException {
      return LiquidGlassCapabilities.none;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LiquidGlassCapabilities>(
        future: _capabilities,
        builder: (context, snapshot) => IosGlassScope(
          capabilities: snapshot.data ?? LiquidGlassCapabilities.none,
          child: widget.child,
        ),
      );
}

class IosGlassScope extends InheritedWidget {
  const IosGlassScope(
      {super.key, required this.capabilities, required super.child});
  final LiquidGlassCapabilities capabilities;
  static LiquidGlassCapabilities of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<IosGlassScope>()
          ?.capabilities ??
      LiquidGlassCapabilities.none;
  @override
  bool updateShouldNotify(IosGlassScope oldWidget) =>
      capabilities != oldWidget.capabilities;
}

/// Keep glass on the navigation/control layer, with solid content cards below.
class IosGlassSurface extends StatelessWidget {
  const IosGlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.border,
  });

  final Widget child;
  final double radius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final caps = IosGlassScope.of(context);
    if (caps.osMajorVersion >= 13 && !kIsWeb) {
      return LiquidGlassContainer(
        shape: radius == 0
            ? const LiquidGlassShape.roundedRectangle(0)
            : LiquidGlassShape.roundedRectangle(radius),
        child: child,
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        caps.reduceTransparency || MediaQuery.highContrastOf(context);
    final background =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final resolvedBorder = border ??
        (radius > 0
            ? Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.18 : 0.65),
                width: 0.7)
            : null);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(alpha: opaque ? 1 : (dark ? 0.80 : 0.72)),
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
        border: resolvedBorder,
      ),
      child: child,
    );
    if (!opaque) {
      surface = BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: surface);
    }
    return radius > 0
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius), child: surface)
        : ClipRect(child: surface);
  }
}

class IosLiquidTabBar extends StatelessWidget {
  const IosLiquidTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<LiquidGlassBarItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final native = IosGlassScope.of(context).osMajorVersion >= 13 && !kIsWeb;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    if (native) {
      return LiquidGlassBottomBar(
        items: items,
        currentIndex: index,
        onTap: onTap,
        height: 85,
        tint: Theme.of(context).colorScheme.primary,
      );
    }

    // 遵循 Apple HIG：标签栏全宽铺满底部，内容高度 50pt，并向下穿透延伸至安全区底端。
    final barHeight = bottomPadding > 0 ? 50.0 + bottomPadding : 58.0;

    return IosGlassSurface(
      radius: 0,
      border: Border(
        top: BorderSide(
          color: IosColors.separator(dark).withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: SizedBox(
        height: barHeight,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: bottomPadding > 0 ? bottomPadding : 4.0,
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: CupertinoTabBar(
              currentIndex: index,
              onTap: onTap,
              height: 50.0,
              iconSize: 26.0,
              backgroundColor: Colors.transparent,
              border: null,
              activeColor: Theme.of(context).colorScheme.primary,
              inactiveColor: CupertinoColors.inactiveGray,
              items: [
                for (final item in items)
                  BottomNavigationBarItem(
                    icon: Icon(item.icon),
                    activeIcon: Icon(item.selectedIcon ?? item.icon),
                    label: item.label,
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scroll views reserve a tail so their final item can clear the floating bar.
double portalBottomInset(BuildContext context) =>
    isApple ? 72 + MediaQuery.viewPaddingOf(context).bottom : 34;
