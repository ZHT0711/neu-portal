import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/pages/shell.dart';

/// 外壳回归：底部导航 5 个目的地正常、无布局溢出。
void main() {
  testWidgets('底部导航栏：5 个目的地正常渲染、无溢出', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final details = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      details.add(d);
      original?.call(d);
    };
    final state = AppState();
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        // 模拟真机中文环境：复现 "No MaterialLocalizations found" 回归
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN')],
        home: const AdaptiveShell(),
      ),
    ));
    try {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } catch (_) {}
    FlutterError.onError = original;

    final localizationErrors = details
        .where((d) => d.exception.toString().contains('MaterialLocalizations'))
        .toList();
    expect(localizationErrors, isEmpty,
        reason: 'zh_CN 下存在本地化查找异常（真机灰屏根因）');

    final overflows =
        details.where((d) => d.exception.toString().contains('overflowed'));
    expect(overflows, isEmpty,
        reason: overflows.map((d) => d.exception).join('\n'));

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['首页', '课表', '服务', '成绩', '我的']) {
      final t = find.text(label);
      expect(t, findsOneWidget, reason: '缺少导航标签 $label');
      final box = tester.renderObject<RenderBox>(t.first);
      expect(box.size.height, greaterThan(5), reason: '$label 标签尺寸异常');
      expect(box.localToGlobal(Offset.zero).dy, lessThan(915),
          reason: '$label 标签被布局到视口外');
    }
  });

  testWidgets('宽屏（≥900）：侧边导航栏正常、无溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = AppState();
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(home: AdaptiveShell()),
    ));
    try {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } catch (_) {}
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('首页'), findsWidgets); // 侧栏标签 + AppBar 标题
  });
}
