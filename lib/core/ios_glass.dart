/// Adaptive iOS navigation materials and lightweight content surfaces.
/// Native mode uses UIKit; custom bars use one clipped backdrop blur.
library;

import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import 'app_state.dart';
import 'platform_style.dart';
import 'tab_scroller.dart';

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
    } catch (_) {
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
  const IosGlassScope({
    super.key,
    required this.capabilities,
    required super.child,
  });
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

/// Content surfaces are opaque by default. Navigation explicitly opts into blur,
/// keeping scrolling lists free of per-card backdrop filters.
class IosGlassSurface extends StatelessWidget {
  const IosGlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.borderRadius,
    this.border,
    this.blurSigma = 0,
    this.specular = false,
    this.tint,
  });

  final Widget child;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;
  final double blurSigma;
  final bool specular;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius =
        borderRadius ?? (radius > 0 ? BorderRadius.circular(radius) : null);
    final hasRadius =
        effectiveRadius != null && effectiveRadius != BorderRadius.zero;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final caps = IosGlassScope.of(context);
    final opaque =
        caps.reduceTransparency || MediaQuery.highContrastOf(context);
    final solid = opaque || blurSigma <= 0;

    // Liquid Glass Substrate
    final baseColor =
        tint ??
        (dark
            ? const Color(0xFF1C1C1E).withValues(alpha: solid ? 1.0 : 0.78)
            : const Color(0xFFFFFFFF).withValues(alpha: solid ? 1.0 : 0.82));

    // Specular Highlight Rim
    final defaultBorder = Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.black.withValues(alpha: 0.06),
      width: 0.75,
    );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: effectiveRadius,
        border: border ?? (hasRadius ? defaultBorder : null),
        boxShadow: hasRadius && !solid
            ? [
                BoxShadow(
                  color: (dark ? Colors.black : const Color(0xFF3553A2))
                      .withValues(alpha: dark ? 0.32 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: specular && !opaque && hasRadius
          ? ClipRRect(
              borderRadius: effectiveRadius,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(
                                alpha: dark ? 0.08 : 0.28,
                              ),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.65],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
            )
          : child,
    );

    if (!opaque && blurSigma > 0) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }

    surface = hasRadius
        ? ClipRRect(borderRadius: effectiveRadius, child: surface)
        : ClipRect(child: surface);

    return RepaintBoundary(child: surface);
  }
}

/// Native tab bar with two Flutter-rendered alternatives.
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
    LiquidTabBarMode mode = LiquidTabBarMode.native;
    try {
      mode = AppScope.of(context).liquidTabBarMode;
    } catch (_) {}

    final caps = IosGlassScope.of(context);
    final hasNative = caps.osMajorVersion >= 13 && !kIsWeb;

    // UIKit supplies its system material on supported iOS versions.
    if (mode == LiquidTabBarMode.native && hasNative) {
      return LiquidGlassBottomBar(
        items: items,
        currentIndex: index,
        onTap: onTap,
        height: 85,
        tint: Theme.of(context).colorScheme.primary,
      );
    }

    // One glass layer with a quiet, neutral selection highlight.
    if (mode == LiquidTabBarMode.fluidCapsule) {
      return _FluidGlassCapsuleBar(
        items: items,
        currentIndex: index,
        onTap: onTap,
      );
    }

    // Full-width navigation and the default fallback.
    return _ClassicGlassTabBar(items: items, index: index, onTap: onTap);
  }
}

/// A single floating material; selected content stays at a stable size.
class _FluidGlassCapsuleBar extends StatelessWidget {
  const _FluidGlassCapsuleBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<LiquidGlassBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottom > 0 ? bottom : 12),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: IosGlassSurface(
            radius: 31,
            blurSigma: 12,
            child: SizedBox(
              height: 62,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Stack(
                  children: [
                    _TabSelection(
                      index: currentIndex,
                      count: items.length,
                      radius: 26,
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _FluidBarDestination(
                              item: items[i],
                              selected: i == currentIndex,
                              onTap: () => onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared selection treatment: no second blur, spring overshoot or icon zoom.
class _TabSelection extends StatelessWidget {
  const _TabSelection({
    required this.index,
    required this.count,
    required this.radius,
  });
  final int index;
  final int count;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedAlign(
          alignment: AlignmentDirectional(
            count < 2 ? 0 : -1 + 2 * index / (count - 1),
            0,
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: FractionallySizedBox(
            widthFactor: 1 / count,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dark ? const Color(0x24FFFFFF) : const Color(0x0E000000),
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FluidBarDestination extends StatelessWidget {
  const _FluidBarDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final LiquidGlassBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? (item.selectedIcon ?? item.icon) : item.icon,
              size: 23,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width material with a soft selection track and a quiet separator.
class _ClassicGlassTabBar extends StatelessWidget {
  const _ClassicGlassTabBar({
    required this.items,
    required this.index,
    required this.onTap,
  });
  final List<LiquidGlassBarItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return IosGlassSurface(
      radius: 0,
      blurSigma: 12,
      border: Border(
        top: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, 4, 6, bottom > 0 ? bottom : 6),
        child: SizedBox(
          height: 56,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Stack(
                  children: [
                    _TabSelection(
                      index: index,
                      count: items.length,
                      radius: 18,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _FluidBarDestination(
                        item: items[i],
                        selected: i == index,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部滑动边距预留
double portalBottomInset(BuildContext context) {
  final shellInset = PortalNavigation.maybeOf(context)?.bottomInset;
  if (shellInset != null) return shellInset;
  if (!isApple) return 34;
  final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
  try {
    final s = AppScope.of(context);
    if (s.liquidTabBarMode == LiquidTabBarMode.fluidCapsule) {
      return 94 + bottomPadding;
    }
  } catch (_) {}
  return 72 + bottomPadding;
}

/// Scroll views reserve a tail so their final item can clear the floating bar.
