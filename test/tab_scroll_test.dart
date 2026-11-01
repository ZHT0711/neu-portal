import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/ios_glass.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/core/tab_scroller.dart';
import 'package:neu_portal/pages/home_page.dart';
import 'package:neu_portal/pages/shell.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setPlatformPreference(PlatformStylePreference.auto);
  }

  ScrollController homeScroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.byType(CustomScrollView),
        ),
      )
      .controller!;

  for (final mode in ['android', 'dockGlass', 'fluidCapsule', 'native']) {
    testWidgets('$mode: reselecting home returns to the top', (tester) async {
      phone(tester);
      final state = AppState();
      int? nativeId;
      final messenger = tester.binding.defaultBinaryMessenger;
      if (mode != 'android') {
        state.liquidTabBarMode = LiquidTabBarMode.values.byName(mode);
      }
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          nativeId = (call.arguments as Map)['id'] as int;
          messenger.setMockMethodCallHandler(
            MethodChannel('real_liquid_glass/tab_bar_$nativeId'),
            (_) async => null,
          );
        }
        return null;
      });
      try {
        debugDefaultTargetPlatformOverride = mode == 'android'
            ? TargetPlatform.android
            : TargetPlatform.iOS;
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: const MaterialApp(
              home: IosGlassScope(
                capabilities: LiquidGlassCapabilities(
                  nativeGlass: true,
                  reduceTransparency: false,
                  osMajorVersion: 26,
                ),
                child: AdaptiveShell(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = homeScroll(tester);
        scroll.jumpTo(700);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        Future<void> tapTab(int index) async {
          if (mode == 'native') {
            expect(find.byType(UiKitView), findsOneWidget);
            expect(nativeId, isNotNull);
            final reply = Completer<void>();
            tester.binding.channelBuffers.push(
              'real_liquid_glass/tab_bar_$nativeId',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('selected', {'index': index}),
              ),
              (_) => reply.complete(),
            );
            await reply.future;
          } else {
            await tester.tap(find.text(index == 0 ? '首页' : '服务').last);
          }
        }

        final offset = scroll.offset;
        await tapTab(2);
        await tester.pumpAndSettle();
        await tapTab(0);
        await tester.pumpAndSettle();
        expect(homeScroll(tester), same(scroll));
        expect(scroll.offset, offset, reason: '正常切回首页应保留原滚动位置');
        await tapTab(0);
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);

        scroll.jumpTo(700);
        await tester.pumpAndSettle();
        await tapTab(0);
        await tester.pump(const Duration(milliseconds: 100));
        await tapTab(0);
        await tester.pumpAndSettle();
        expect(scroll.offset, 0, reason: '双击同样应回顶');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (nativeId != null) {
          messenger.setMockMethodCallHandler(
            MethodChannel('real_liquid_glass/tab_bar_$nativeId'),
            null,
          );
        }
        state.dispose();
      }
    });
  }

  testWidgets('replacing home does not unregister the new scroll controller', (
    tester,
  ) async {
    phone(tester);
    final state = AppState();
    addTearDown(state.dispose);
    var generation = 0;
    late StateSetter replace;
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              replace = setState;
              return HomePage(key: ValueKey(generation));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    replace(() => generation++);
    await tester.pumpAndSettle();
    final scroll = homeScroll(tester);
    scroll.jumpTo(700);
    await tester.pumpAndSettle();
    TabScroller.scrollToTop(0);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });

  testWidgets('Reduce Motion returns home to the top immediately', (
    tester,
  ) async {
    phone(tester);
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: AdaptiveShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = homeScroll(tester);
    scroll.jumpTo(700);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页').last);
    await tester.pump();
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
  });
}
