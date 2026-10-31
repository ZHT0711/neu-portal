/// Material 3 主题 — 种子色取自门户 site/info 的 theme_color (#3553A2)。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'models.dart';

class NeuColors {
  static const seed = Color(0xFF3553A2);

  /// 课表课程色板：一组和谐、对比充分的种子系色调。
  static const coursePalette = <Color>[
    Color(0xFFE26C39), // 焰橙
    Color(0xFF3553A2), // 东大蓝
    Color(0xFF1E7A5A), // 松绿
    Color(0xFF8C3FA8), // 紫罗兰
    Color(0xFFB4345C), // 玫红
    Color(0xFF006874), // 孔雀蓝
    Color(0xFF7A5900), // 鎏金
    Color(0xFF5B5B97), // 藤紫
  ];

  static Color courseColor(String name, int indexInDay) {
    final h = name.hashCode.abs();
    return coursePalette[(h + indexInDay) % coursePalette.length];
  }

  static Color avatarColor(String seedText) =>
      coursePalette[seedText.hashCode.abs() % coursePalette.length];

  /// 课程 / 考试 / 自定义日程的色调。
  static Color slotTone(CourseSlot slot) {
    switch (slot.kind) {
      case 'exam':
        return const Color(0xFFB4345C);
      case 'custom':
        return const Color(0xFF006874);
      default:
        return courseColor(slot.name, 0);
    }
  }
}

class NeuTheme {
  static ThemeData light(Color seed) => _base(seed, Brightness.light);
  static ThemeData dark(Color seed) => _base(seed, Brightness.dark);

  static ThemeData _base(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isLight = brightness == Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFF7F8FC) : scheme.surface,
      // Web 上墨滴会铺满整屏 Material（大画布下还会触发光栅化问题），
      // 用无墨滴 + 高亮反馈；移动端保留 Material 3 的 InkSparkle。
      splashFactory: kIsWeb ? NoSplash.splashFactory : InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 轻量中文日期工具（不引入 intl，规避版本锁）。
class Fmt {
  static const weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String monthDay(DateTime d) => '${d.month}月${d.day}日';

  static String full(DateTime d) =>
      '${d.year}年${d.month}月${d.day}日 ${weekNames[d.weekday - 1]}';

  /// ISO 日期 “2026-10-27” → “10月27日”。
  static String isoToCn(String iso) {
    final p = iso.split('-');
    if (p.length < 3) return iso;
    return '${int.parse(p[1])}月${int.parse(p[2])}日';
  }

  /// 问候语。
  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return '夜深了';
    if (h < 9) return '早上好';
    if (h < 12) return '上午好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }
}
