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
import 'package:flutter/cupertino.dart';

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
  static const double rSm = 8; // 小组件（徽标、码块）
  static const double rMd = 12; // 列表、按钮
  static const double rLg = 16; // 卡片
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

  static Color adaptiveTone(BuildContext context, Color tone) =>
      Theme.of(context).brightness == Brightness.dark
          ? ColorScheme.fromSeed(seedColor: tone, brightness: Brightness.dark)
              .primary
          : tone;

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
  static ThemeData light(Color seed,
          {bool ios = false, ColorScheme? dynamicScheme}) =>
      _base(seed, Brightness.light, ios: ios, dynamicScheme: dynamicScheme);
  static ThemeData dark(Color seed,
          {bool ios = false, ColorScheme? dynamicScheme}) =>
      _base(seed, Brightness.dark, ios: ios, dynamicScheme: dynamicScheme);

  static ThemeData _base(Color seed, Brightness brightness,
      {bool ios = false, ColorScheme? dynamicScheme}) {
    final dark = brightness == Brightness.dark;
    final generated = dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final surface = IosColors.systemGroupedBackground(dark);
    final cardColor = IosColors.secondaryGroupedBackground(dark);
    final scheme = ios
        ? generated.copyWith(
            surface: surface,
            surfaceContainerLow: cardColor,
            surfaceContainer: cardColor,
            surfaceContainerHigh:
                dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            onSurface: IosColors.label(dark),
            onSurfaceVariant:
                dark ? const Color(0xFFAEAEB2) : const Color(0xFF636366),
            outlineVariant: IosColors.separator(dark),
          )
        : generated;
    final text = ios
        ? Typography.material2021()
            .englishLike
            .apply(
              fontFamily: 'CupertinoSystemText',
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            )
            .merge(const TextTheme(
              headlineLarge:
                  TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
              headlineMedium:
                  TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              headlineSmall:
                  TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              bodyLarge: TextStyle(fontSize: 17),
              bodyMedium: TextStyle(fontSize: 15),
              bodySmall: TextStyle(fontSize: 13),
              labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ))
        : Typography.material2021().englishLike.apply(
              fontFamily: 'Roboto',
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            );
    final radius = ios ? Ds.rMd : Ds.rLg;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: scheme.primary,
        scaffoldBackgroundColor: ios ? surface : scheme.surface,
        barBackgroundColor: ios ? cardColor : scheme.surface,
      ),
      brightness: brightness,
      platform: ios ? TargetPlatform.iOS : TargetPlatform.android,
      scaffoldBackgroundColor: ios ? surface : scheme.surface,
      splashFactory:
          ios || kIsWeb ? NoSplash.splashFactory : InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: ios ? cardColor : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: ios ? 0 : 3,
        surfaceTintColor: ios ? Colors.transparent : scheme.surfaceTint,
        centerTitle: ios,
        titleTextStyle: ios ? text.titleMedium : text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: ios ? cardColor : scheme.surfaceContainerLow,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
            color: st.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant)),
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
              fontSize: 12,
              color: scheme.onSurface,
              fontWeight: st.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rMd)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ios ? Ds.rMd : Ds.full)),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ios ? Ds.rMd : Ds.full)),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ios ? cardColor : scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.rMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.rMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      chipTheme: ChipThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rSm)),
        labelStyle: text.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rMd)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rMd)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: !ios,
        backgroundColor: ios ? cardColor : scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.rXl)),
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
