/// Material 3 设计系统 — 设计令牌 + 组件主题。
/// 种子色取自门户 site/info 的 theme_color (#3553A2)。
///
/// 规则：
/// - 间距走 4dp 网格（Ds.*），圆角走 MD3 形状比例（Ds.r*）
/// - 文字一律用 textTheme 角色，不写散装 fontSize/weight
/// - 表面用 tonal 色（surfaceContainer*），不用投影
/// - 品牌色 primary 用于强调；tertiary 仅用于徽标/特殊状态
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'models.dart';
import 'platform_style.dart' show IosColors;

/// 设计令牌。
abstract final class Ds {
  // ── 间距（4dp 网格）──
  static const double gutter = 16; // 页面左右留白
  static const double blockV = 24; // 分区间距
  static const double cardPadH = 16; // 卡片内水平
  static const double cardPadV = 12; // 卡片内垂直

  // ── 圆角（MD3 形状比例）──
  static const double rSm = 10; // 小组件（徽标、码块）
  static const double rMd = 14; // 列表、按钮
  static const double rLg = 18; // 卡片
  static const double rXl = 28; // 大卡 / 英雄区
  static const double full = 999;
}

class NeuColors {
  static const seed = Color(0xFF3553A2);

  /// 课表课程色板（MD3 tonal 调色板的种子组）。
  static const coursePalette = <Color>[
    Color(0xFFB93815), // 陶橙
    Color(0xFF3553A2), // 东大蓝
    Color(0xFF226C4F), // 松绿
    Color(0xFF7D4AA0), // 紫藤
    Color(0xFFA93558), // 玫红
    Color(0xFF00696E), // 孔雀
    Color(0xFF775A2B), // 赭金
    Color(0xFF5064A8), // 靛蓝
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
        return const Color(0xFFA93558);
      case 'custom':
        return const Color(0xFF00696E);
      default:
        return courseColor(slot.name, 0);
    }
  }
}

class NeuTheme {
  static ThemeData light(Color seed, {bool ios = false}) =>
      _base(seed, Brightness.light, ios: ios);
  static ThemeData dark(Color seed, {bool ios = false}) =>
      _base(seed, Brightness.dark, ios: ios);

  static TextTheme _text(ColorScheme s) {
    final base = Typography.material2021();
    final english = base.englishLike;
    return english.apply(
      bodyColor: s.onSurface,
      displayColor: s.onSurface,
      fontSizeFactor: 1,
      fontSizeDelta: 0,
    ).merge(const TextTheme(
      // M3 字阶（移动端基线）
      headlineSmall: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 15, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35),
      bodySmall: TextStyle(fontSize: 12, height: 1.3),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2),
      labelSmall: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          height: 1.2,
          letterSpacing: 0.2),
    ));
  }

  static ThemeData _base(Color seed, Brightness brightness,
      {bool ios = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isLight = brightness == Brightness.light;
    final text = _text(scheme);

    final scheme0 = ios
        ? scheme.copyWith(
            primary: const Color(0xFF3553A2), // HIG 强调色：品牌蓝原色
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFDDE3F5),
            onPrimaryContainer: const Color(0xFF1B2A55),
          )
        : scheme;

    // iOS（HIG）：系统分组背景 + 白卡 + 连续圆角 12；顶栏透明（玻璃由外壳绘制）
    final dark = brightness == Brightness.dark;
    final surface = ios
        ? IosColors.systemGroupedBackground(dark)
        : scheme0.surface;
    final cardColor = ios
        ? IosColors.secondaryGroupedBackground(dark)
        : scheme0.surfaceContainerLow;
    final radius = ios ? Ds.rMd : Ds.rLg;

    return ThemeData(
      colorScheme: scheme0,
      brightness: brightness,
      platform: ios ? TargetPlatform.iOS : TargetPlatform.android,
      scaffoldBackgroundColor: surface,
      splashFactory: kIsWeb ? NoSplash.splashFactory : InkSparkle.splashFactory,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor:
            ios ? Colors.transparent : scheme.surface,
        foregroundColor:
            ios ? IosColors.label(isLight ? false : true) : scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: ios,
        titleTextStyle: ios
            ? TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: IosColors.label(isLight ? false : true))
            : text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
            (st) => IconThemeData(color: scheme.onSurfaceVariant)),
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
              fontSize: 12,
              fontWeight: st.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ds.rMd)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Ds.rMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Ds.rMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.rMd),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ds.rSm)),
        labelStyle: text.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ds.rMd)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rMd)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Ds.rXl)),
        ),
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
