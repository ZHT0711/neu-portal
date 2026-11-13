import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neu_portal/app.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/ios_glass.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/pages/login_page.dart';
import 'package:neu_portal/pages/services_page.dart';
import 'package:neu_portal/pages/shell.dart';
import 'package:neu_portal/widgets/common.dart';

const previews = bool.fromEnvironment('UI_PREVIEWS');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void platformTest(String description, TargetPlatform platform,
      Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        debugDefaultTargetPlatformOverride = platform;
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUpAll(() async {
    // Optional local previews use a real Chinese font; CI needs no host fonts.
    if (previews) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.SF Pro Text',
        '.SF Pro Display'
      ]) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
      for (final entry in {
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        'packages/cupertino_icons/${CupertinoIcons.iconFont}':
            'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      }.entries) {
        final bytes = await rootBundle.load(entry.value);
        await (FontLoader(entry.key)..addFont(Future.value(bytes))).load();
      }
    }
  });

  Future<AppState> launch(WidgetTester tester, TargetPlatform platform,
      {double scale = 1, double width = 390, bool dark = false}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState()
      ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    addTearDown(state.dispose);
    await tester.pumpWidget(Builder(
        builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: NEUPortalApp(state: state),
            )));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (previews) {
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../outputs/ui/$name.png'));
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final name = platform == TargetPlatform.iOS ? 'ios' : 'android';
    platformTest(
        '$name: shortcuts retain tab navigation and search state', platform,
        (tester) async {
      await launch(tester, platform);
      expect(
          find.byType(
              platform == TargetPlatform.iOS ? IosLiquidTabBar : NavigationBar),
          findsOneWidget);
      await capture(tester, '$name-home');
      await tester.ensureVisible(find.text('服务大厅'));
      await tester.tap(find.text('服务大厅'));
      await tester.pumpAndSettle();
      expect(find.byType(ServicesPage), findsOneWidget);
      final field = find.descendant(
          of: find.byType(AdaptiveSearchField),
          matching: find.byType(EditableText));
      await tester.enterText(field, '不存在的服务');
      await tester.pumpAndSettle();
      expect(find.textContaining('本地没有匹配'), findsOneWidget);
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('服务').last);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).controller.text, '不存在的服务');
      await tester.tap(platform == TargetPlatform.iOS
          ? find.byIcon(CupertinoIcons.xmark_circle_fill)
          : find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      await capture(tester, '$name-services');
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('动态取色 (Material You)'),
          platform == TargetPlatform.iOS ? findsNothing : findsOneWidget);
      await capture(tester, '$name-profile');
      expect(tester.takeException(), isNull);
    });

    platformTest(
        '$name: narrow screen, larger text and dark mode remain usable',
        platform, (tester) async {
      final state =
          await launch(tester, platform, width: 320, scale: 1.3, dark: true);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      final segments = find.byType(AdaptiveSegments<ThemeMode>);
      await tester.ensureVisible(segments);
      await tester
          .tap(find.descendant(of: segments, matching: find.text('浅色')));
      await tester.pumpAndSettle();
      expect(state.themeMode, ThemeMode.light);
      await tester
          .tap(find.descendant(of: segments, matching: find.text('深色')));
      await tester.pumpAndSettle();
      expect(state.themeMode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('服务').last);
      await tester.pumpAndSettle();
      await capture(tester, '$name-small-dark-services');
      expect(tester.takeException(), isNull);
    });

    platformTest(
        '$name: schedule editor scrolls above the keyboard and saves', platform,
        (tester) async {
      final state = await launch(tester, platform, width: 320, scale: 1.3);
      await tester.tap(find.text('课表').last);
      await tester.pumpAndSettle();
      if (platform == TargetPlatform.iOS) {
        await tester.tap(find.byIcon(CupertinoIcons.add));
      } else {
        await tester.tap(find.text('添加日程'));
      }
      await tester.pumpAndSettle();
      final title = find.byType(TextField).first;
      await tester.enterText(title, '界面体验验证');
      await tester.tap(find.text('日期'));
      await tester.pumpAndSettle();
      expect(
          find.byType(platform == TargetPlatform.iOS
              ? CupertinoDatePicker
              : DatePickerDialog),
          findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final save = find.text('保存到本机课表');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(state.events.single.name, '界面体验验证');
      expect(tester.takeException(), isNull);
    });

    platformTest(
        '$name: login validates inline and remains scrollable with keyboard',
        platform, (tester) async {
      await launch(tester, platform, width: 320, scale: 1.3);
      final context = tester.element(find.byType(MaterialApp));
      final navigator =
          Navigator.of(tester.element(find.byType(AdaptiveShell)));
      navigator
          .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
      await tester.pumpAndSettle();
      await capture(tester, '$name-login');
      final login = find.byType(AdaptiveFilledButton).last;
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.text('请输入学号/工号和密码'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(login);
      expect(tester.getBottomLeft(login).dy, lessThan(544));
      expect(tester.takeException(), isNull);
      expect(context.mounted, isTrue);
    });
  }

  testWidgets('Reduce Motion exposes final values immediately', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(body: StaggerIn(index: 8, child: CountUpText('88.5'))),
    )));
    expect(find.text('88.5'), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsNothing);
    await tester.pumpAndSettle();
  });
}
