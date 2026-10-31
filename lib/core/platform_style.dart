/// 平台自适应样式层：iOS 遵循 HIG（含液态玻璃材质），Android 遵循 MD3。
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 是否为苹果平台（iOS/macOS 走 HIG 风格层）。
bool get isApple =>
    !kIsWeb &&
    (Platform.isIOS || Platform.isMacOS);

/// iOS 系统色（HIG 语义色，深浅色各自对应）。
class IosColors {
  IosColors._();

  static Color systemGroupedBackground(bool dark) =>
      dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  static Color secondaryGroupedBackground(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  static Color separator(bool dark) =>
      dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);
  static Color label(bool dark) =>
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color secondaryLabel(bool dark) =>
      dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43);
}

/// 液态玻璃容器：背景高斯模糊 + 半透明材质层（iOS 26 Liquid Glass 观感）。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.dark = false,
    this.blur = 28,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool dark;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            // 半透明材质层：亮色白雾 / 暗色深玻璃
            color: dark
                ? const Color(0xCC1C1C1E)
                : Colors.white.withValues(alpha: 0.68),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 页面顶栏：iOS 用玻璃材质 + 居中标题（HIG），Android 走 MD3 主题。
class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PageAppBar({super.key, this.title, this.actions = const []});

  final String? title;
  final List<Widget> actions;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (isApple) {
      final scheme = Theme.of(context).colorScheme;
      return AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(title ?? '',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: IosColors.label(dark))),
        actions: actions,
        flexibleSpace: GlassContainer(
          dark: dark,
          child: const SizedBox.expand(),
        ),
      );
    }
    return AppBar(
      title: title == null ? null : Text(title!),
      actions: actions,
    );
  }
}

/// 底栏图标文案（iOS 标签栏样式：SF 尺寸，激活色 = 主题色）。
class TabBarItem extends StatelessWidget {
  const TabBarItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.color,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(active ? activeIcon : icon, size: 24, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 触感反馈。
Future<void> hapticLight() => HapticFeedback.lightImpact();
Future<void> hapticSelect() => HapticFeedback.selectionClick();
