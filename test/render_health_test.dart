import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/pages/grades_page.dart';
import 'package:neu_portal/pages/home_page.dart';
import 'package:neu_portal/pages/profile_page.dart';
import 'package:neu_portal/pages/schedule_page.dart';
import 'package:neu_portal/pages/services_page.dart';

/// 渲染树体检：泵起每个页面，找出尺寸异常（非有限 / 超过视口数量级）的盒子，
/// 以及“巨型输入框”——用于复现 Web 端大灰块问题。
void main() {
  Future<(AppState, WidgetTester)> pumpPage(
      WidgetTester tester, Widget page) async {
    final state = AppState();
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(home: page),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return (state, tester);
  }

  List<String> giantBoxes(WidgetTester tester, Size window) {
    final problems = <String>[];
    final seen = <RenderObject>{};
    for (final el in tester.allElements) {
      final ro = el.findRenderObject();
      if (ro is! RenderBox || !seen.add(ro)) continue;
      try {
        final size = ro.size;
        final bad = !size.width.isFinite ||
            !size.height.isFinite ||
            size.width > window.width * 20 ||
            size.height > window.height * 20;
        if (bad) {
          problems.add(
              '${el.widget.runtimeType} → ${ro.runtimeType} size=$size');
        }
      } catch (_) {}
    }
    return problems;
  }

  testWidgets('服务页：无巨型组件，搜索框高度正常', (tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, const ServicesPage());
    final problems = giantBoxes(tester, tester.view.physicalSize /
        tester.view.devicePixelRatio);
    expect(problems, isEmpty, reason: problems.join('\n'));
    // 标题栏底部搜索框高度应正常（≤ 90），而不是被撑满全屏
    for (final t in tester.widgetList<TextField>(find.byType(TextField))) {
      final ro = tester.renderObject<RenderBox>(find.byWidget(t));
      expect(ro.size.height, lessThan(120),
          reason: 'TextField 尺寸异常：${ro.size}');
    }
  });

  testWidgets('首页：无巨型组件', (tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, const HomePage());
    final problems = giantBoxes(
        tester, tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  testWidgets('课表页：无巨型组件', (tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, const SchedulePage());
    await tester.pump(const Duration(milliseconds: 100));
    final problems = giantBoxes(
        tester, tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  testWidgets('成绩页 / 我的页：无巨型组件', (tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, const GradesPage());
    var problems = giantBoxes(
        tester, tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(problems, isEmpty, reason: problems.join('\n'));
    await pumpPage(tester, const ProfilePage());
    problems = giantBoxes(
        tester, tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
