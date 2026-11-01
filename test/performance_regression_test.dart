import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/app.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/core/theme.dart';
import 'package:neu_portal/pages/services_page.dart';
import 'package:neu_portal/pages/home_page.dart';
import 'package:neu_portal/pages/shell.dart';
import 'package:neu_portal/widgets/common.dart';
import 'package:neu_portal/widgets/neu_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previews = bool.fromEnvironment('UI_PREVIEWS');

class _RefreshableState extends AppState {
  void refreshData() => notifyListeners();
}

class _MountProbe extends StatefulWidget {
  const _MountProbe(this.onMount);
  final VoidCallback onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('home'));
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
    for (final family in ['Roboto', 'CupertinoSystemText']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void platformTest(
    String name,
    TargetPlatform platform,
    WidgetTesterCallback body,
  ) {
    testWidgets(name, (tester) async {
      try {
        debugDefaultTargetPlatformOverride = platform;
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    platformTest(
      '$platform: service grids build only visible items',
      platform,
      (tester) async {
        phone(tester);
        debugDefaultTargetPlatformOverride = platform;
        final state = AppState()
          ..apps = List.generate(
            1000,
            (i) => PortalApp(name: 'App $i', url: '', category: 'Campus'),
          )
          ..services = [
            ServiceSection(
              'Topic',
              List.generate(1000, (i) => ServiceEntry('Service $i')),
            ),
          ];
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: const MaterialApp(home: ServicesPage()),
          ),
        );
        await tester.pumpAndSettle();
        final tiles = find.byType(AppTile).evaluate().length;
        expect(tiles, greaterThan(0));
        expect(
          tiles,
          lessThan(60),
          reason: '1000 apps must not all mount at once',
        );
        expect(find.text('Service 999'), findsNothing);

        final scroll = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        // 跳到专题服务，确认后续网格仍按需创建且能到达末项。
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text('Service 999'), findsOneWidget);
        expect(find.byType(AppTile), findsNothing);
        scroll.controller!.jumpTo(0);
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byType(AdaptiveSearchField),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, 'Service 999');
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'Service 999',
          ),
          findsOneWidget,
        );
        expect(find.text('Service 998'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    platformTest(
      '$platform: returning to services is opaque on first frame',
      platform,
      (tester) async {
        phone(tester);
        debugDefaultTargetPlatformOverride = platform;
        final state = AppState();
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: const MaterialApp(home: AdaptiveShell()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('服务').last);
        await tester.pumpAndSettle();
        final serviceState = tester.state(find.byType(ServicesPage));
        await tester.tap(find.text('首页').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('服务').last);
        await tester.pump();
        final page = find.byType(ServicesPage);
        expect(tester.state(page), same(serviceState));
        expect(
          find.ancestor(of: page, matching: find.byType(AnimatedOpacity)),
          findsNothing,
        );
        expect(TickerMode.valuesOf(tester.element(page)).enabled, isTrue);
        expect(
          TickerMode.valuesOf(
            tester.element(find.byType(HomePage, skipOffstage: false)),
          ).enabled,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
      },
    );

    for (final dark in [false, true]) {
      platformTest(
        '$platform: splash ${dark ? 'dark' : 'light'} preserves its child',
        platform,
        (tester) async {
          phone(tester);
          debugDefaultTargetPlatformOverride = platform;
          var mounts = 0;
          await tester.pumpWidget(
            MaterialApp(
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
              home: NeuSplashView(child: _MountProbe(() => mounts++)),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.runAsync(
            () => precacheImage(
              tester.widget<Image>(find.byType(Image)).image,
              tester.element(find.byType(NeuSplashView)),
            ),
          );
          await tester.pump();
          expect(find.text('东北大学 · 一号通'), findsOneWidget);
          expect(find.byType(BackdropFilter), findsNothing);
          final crest = tester.widget<Image>(find.byType(Image));
          expect(crest.color, dark ? isNotNull : isNull);
          if (_previews) {
            final name = platform == TargetPlatform.iOS ? 'ios' : 'android';
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../outputs/ui/$name-splash-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
          final before = tester.state(find.byType(_MountProbe));
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          expect(find.text('东北大学 · 一号通'), findsNothing);
          expect(mounts, 1);
          expect(tester.state(find.byType(_MountProbe)), same(before));
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }

  testWidgets('slow startup respects readiness but has a bounded wait', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NeuSplashView(isReady: false, child: Scaffold())),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('东北大学 · 一号通'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('东北大学 · 一号通'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('Reduce Motion bypasses the splash without residual animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: NeuSplashView(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    expect(find.text('东北大学 · 一号通'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'ready data dismisses after the minimum without waiting for the guard',
    (tester) async {
      var ready = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return NeuSplashView(isReady: ready, child: const Scaffold());
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.text('东北大学 · 一号通'), findsOneWidget);
      update(() => ready = true);
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      await tester.pumpAndSettle();
      expect(find.text('东北大学 · 一号通'), findsNothing);
    },
  );

  testWidgets('disposing startup early cancels timers and tickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NeuSplashView(child: Scaffold())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('data updates reuse themes and appearance changes still apply', (
    tester,
  ) async {
    phone(tester);
    final state = _RefreshableState();
    addTearDown(state.dispose);
    await tester.pumpWidget(NEUPortalApp(state: state));
    await tester.pumpAndSettle();
    final before = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme;
    state.refreshData();
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
      same(before),
    );
    await state.setSeedColor(Colors.green);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
      isNot(same(before)),
    );
    await state.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AdaptiveShell))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
