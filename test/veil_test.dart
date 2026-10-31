import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/pages/shell.dart';

void main() {
  testWidgets('切到服务页：检查 ModalBarrier 与卡死动画', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = AppState();
    await tester.pumpWidget(AppScope(
      state: state,
      child: const MaterialApp(home: AdaptiveShell()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('服务'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    // 1) 卡死动画检测：pumpAndSettle 若超时说明有动画永不停止
    var settled = true;
    try {
      await tester.pumpAndSettle(const Duration(seconds: 3));
    } catch (_) {
      settled = false;
    }
    // ignore: avoid_print
    print('settled: $settled');
    // ignore: avoid_print
    print('transientCallbacks: ${tester.binding.transientCallbackCount}');

    // 2) 遮罩检测
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).toList();
    for (var i = 0; i < barriers.length; i++) {
      // ignore: avoid_print
      print('barrier[$i] color=${barriers[i].color} dismissible=${barriers[i].dismissible}');
    }
    final dimmed = barriers.where((b) => b.color != null && b.color!.toARGB32() & 0xFF > 0).length;
    // ignore: avoid_print
    print('non-transparent barriers: $dimmed');

    expect(settled, isTrue, reason: '有动画卡死（未 settle），导致半透明遮罩残留');
    expect(dimmed, 0, reason: '存在非透明 ModalBarrier（全屏变暗的元凶）');
  });
}
