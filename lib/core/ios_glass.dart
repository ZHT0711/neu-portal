/// Native iOS Liquid Glass, with a readable Flutter fallback for previews.
library;

import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

class IosGlassEnvironment extends StatefulWidget {
  const IosGlassEnvironment({super.key, required this.child});
  final Widget child;
  @override
  State<IosGlassEnvironment> createState() => _IosGlassEnvironmentState();
}

class _IosGlassEnvironmentState extends State<IosGlassEnvironment> {
  late final Future<LiquidGlassCapabilities> _capabilities = _probe();
  Future<LiquidGlassCapabilities> _probe() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
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
  const IosGlassSurface({super.key, required this.child, this.radius = 24});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final caps = IosGlassScope.of(context);
    if (caps.osMajorVersion >= 13 && !kIsWeb) {
      return LiquidGlassContainer(
        shape: LiquidGlassShape.roundedRectangle(radius),
        child: child,
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        caps.reduceTransparency || MediaQuery.highContrastOf(context);
    final background =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(alpha: opaque ? 1 : (dark ? 0.80 : 0.72)),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: Colors.white.withValues(alpha: dark ? 0.18 : 0.65),
            width: 0.7),
      ),
      child: child,
    );
    if (!opaque) {
      surface = BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: surface);
    }
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius), child: surface);
  }
}

class IosLiquidTabBar extends StatelessWidget {
  const IosLiquidTabBar(
      {super.key,
      required this.items,
      required this.index,
      required this.onTap});
  final List<LiquidGlassBarItem> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final native = IosGlassScope.of(context).osMajorVersion >= 13 && !kIsWeb;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: native
            ? LiquidGlassBottomBar(
                items: items,
                currentIndex: index,
                onTap: onTap,
                height: 64,
                tint: Theme.of(context).colorScheme.primary,
              )
            : IosGlassSurface(
                radius: 32,
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: CupertinoTabBar(
                    currentIndex: index,
                    onTap: onTap,
                    height: 64,
                    iconSize: 25,
                    backgroundColor: Colors.transparent,
                    border: null,
                    activeColor: Theme.of(context).colorScheme.primary,
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
    defaultTargetPlatform == TargetPlatform.iOS
        ? 112 + MediaQuery.viewPaddingOf(context).bottom
        : 34;
