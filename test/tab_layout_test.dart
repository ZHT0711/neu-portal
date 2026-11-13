import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/ios_glass.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/core/theme.dart';
import 'package:neu_portal/pages/grades_page.dart';
import 'package:neu_portal/pages/home_page.dart';
import 'package:neu_portal/pages/profile_page.dart';
import 'package:neu_portal/pages/schedule_page.dart';
import 'package:neu_portal/pages/services_page.dart';
import 'package:neu_portal/pages/shell.dart';
import 'package:neu_portal/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previews = bool.fromEnvironment('UI_PREVIEWS');

void _layoutTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setPlatformPreference(PlatformStylePreference.auto);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    setPlatformPreference(PlatformStylePreference.auto);
  });

  setUpAll(() async {
    if (!_previews) return;
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/${CupertinoIcons.iconFont}':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  Future<AppState> launch(
    WidgetTester tester, {
    Widget page = const AdaptiveShell(),
    TargetPlatform platform = TargetPlatform.iOS,
    double width = 390,
    double scale = 1,
    bool dark = false,
    bool reducedMotion = false,
    LiquidTabBarMode mode = LiquidTabBarMode.fluidCapsule,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = platform;
    final state = AppState()..liquidTabBarMode = mode;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark
              ? NeuTheme.dark(
                  NeuColors.seed,
                  ios: platform == TargetPlatform.iOS,
                )
              : NeuTheme.light(
                  NeuColors.seed,
                  ios: platform == TargetPlatform.iOS,
                ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    return state;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    _layoutTest(
      '$platform: idle preparation removes first-tap mounting and list fades',
      (tester) async {
        await launch(tester, platform: platform);
        // Preparation waits for the home entrance, then mounts one tab per frame.
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final states = <Type, State>{};
        for (final type in [
          SchedulePage,
          ServicesPage,
          GradesPage,
          ProfilePage,
        ]) {
          final page = find.byType(type, skipOffstage: false);
          expect(page, findsOneWidget, reason: 'Prepared before any tap');
          states[type] = tester.state(page);
          expect(Focus.of(tester.element(page)).canRequestFocus, isFalse);
        }
        for (final entry in {
          '课表': SchedulePage,
          '服务': ServicesPage,
          '成绩': GradesPage,
          '我的': ProfilePage,
        }.entries) {
          await tester.tap(find.text(entry.key).last);
          await tester.pump();
          final page = find.byType(entry.value);
          expect(tester.state(page), same(states[entry.value]));
          // Cupertino controls have their own internal fades; only list-entry
          // wrappers must be bypassed for instant tab contents.
          for (final stagger
              in find
                  .descendant(of: page, matching: find.byType(StaggerIn))
                  .evaluate()) {
            expect(
              find.descendant(
                of: find.byWidget(stagger.widget),
                matching: find.byType(AnimatedSlide),
              ),
              findsNothing,
            );
          }
          expect(TickerMode.valuesOf(tester.element(page)).enabled, isTrue);
          expect(
            TickerMode.valuesOf(
              tester.element(find.byType(HomePage, skipOffstage: false)),
            ).enabled,
            isFalse,
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );

    for (final width in [320.0, 390.0]) {
      _layoutTest(
        '$platform: schedule columns align at width $width and larger text',
        (tester) async {
          await launch(
            tester,
            platform: platform,
            page: const SchedulePage(),
            width: width,
            scale: 1.3,
          );
          await tester.pumpAndSettle();
          void checkGeometry() {
            final periodHeader = tester.getRect(
              find.byKey(const ValueKey('schedule-period-header')),
            );
            final firstRow = tester.getRect(
              find.byKey(const ValueKey('schedule-period-0')),
            );
            double? dayWidth;
            for (var day = 1; day <= 7; day++) {
              final header = tester.getRect(
                find.byKey(ValueKey('schedule-day-header-$day')),
              );
              final body = tester.getRect(
                find.byKey(ValueKey('schedule-day-body-$day')),
              );
              expect(header.top, closeTo(periodHeader.top, 0.01));
              expect(header.bottom, closeTo(periodHeader.bottom, 0.01));
              expect(body.top, closeTo(firstRow.top, 0.01));
              expect(body.height, closeTo(firstRow.height * 5, 0.01));
              expect(body.width, closeTo(dayWidth ?? body.width, 0.01));
              dayWidth = body.width;
            }
          }

          checkGeometry();
          if (_previews && width == 390) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../outputs/ui/${platform.name}-schedule-aligned.png',
              ),
            );
          }
          await tester.tap(find.text('整周一屏'));
          await tester.pumpAndSettle();
          checkGeometry();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final mode in [
    LiquidTabBarMode.fluidCapsule,
    LiquidTabBarMode.dockGlass,
  ]) {
    for (final dark in [false, true]) {
      _layoutTest(
        '$mode: ${dark ? 'dark' : 'light'} navigation keeps one material and respects Reduce Motion',
        (tester) async {
          await launch(
            tester,
            mode: mode,
            dark: dark,
            reducedMotion: true,
            width: 320,
            scale: 1.3,
          );
          await tester.pumpAndSettle();
          final bar = find.byType(IosLiquidTabBar);
          expect(
            find.descendant(of: bar, matching: find.byType(BackdropFilter)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: bar, matching: find.byType(AnimatedScale)),
            findsNothing,
          );
          await tester.tap(find.text('课表').last);
          await tester.pump();
          final align = tester.widget<AnimatedAlign>(
            find.descendant(of: bar, matching: find.byType(AnimatedAlign)),
          );
          expect(align.duration, Duration.zero);
          expect(tester.takeException(), isNull);
          if (_previews) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../outputs/ui/ios-${mode.name}-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
          await tester.pumpAndSettle();
        },
      );
    }
  }

  _layoutTest('iOS content surfaces skip blur unless navigation requests it', (
    tester,
  ) async {
    await launch(tester, page: const GradesPage());
    await tester.pumpAndSettle();
    for (final element in find.byType(IosGlassSurface).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    }
    expect(find.byType(StaggerIn), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  if (_previews) {
    for (final mode in [
      LiquidTabBarMode.fluidCapsule,
      LiquidTabBarMode.dockGlass,
    ]) {
      _layoutTest('iOS $mode standard phone preview', (tester) async {
        await launch(tester, mode: mode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('课表').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .getBottomLeft(find.byKey(const ValueKey('schedule-period-4')))
              .dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(IosLiquidTabBar)).dy),
          reason:
              'The last course must clear navigation and the home indicator',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../outputs/ui/ios-${mode.name}-phone.png'),
        );
      });
    }
  }
}
