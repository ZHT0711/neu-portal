import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/platform_style.dart';
import 'package:neu_portal/pages/services_page.dart';

void main() {
  testWidgets('diagnostic service search benchmark (10k apps, 2k services)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState()
      ..apps = List.generate(
        10000,
        (i) => PortalApp(
          name: 'Synthetic app $i',
          url: '',
          category: 'Category ${i % 12}',
          desc: 'Synthetic description with item number $i',
        ),
      )
      ..services = [
        for (var section = 0; section < 20; section++)
          ServiceSection('Synthetic topic $section', [
            for (var entry = 0; entry < 100; entry++)
              ServiceEntry('Synthetic service ${section * 100 + entry}'),
          ]),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: ServicesPage()),
      ),
    );
    await tester.pumpAndSettle();
    final onChanged = tester
        .widget<AdaptiveSearchField>(find.byType(AdaptiveSearchField))
        .onChanged;

    Future<int> sample(String query) async {
      final stopwatch = Stopwatch()..start();
      onChanged(query);
      await tester.pump(const Duration(milliseconds: 100));
      stopwatch.stop();
      return stopwatch.elapsedMicroseconds;
    }

    final cold = await sample('synthetic-no-match-cold');
    final warm = <int>[];
    for (var i = 0; i < 25; i++) {
      warm.add(await sample('synthetic-no-match-warm-$i'));
    }
    warm.sort();
    final median = warm[warm.length ~/ 2];
    final p95 = warm[(warm.length * 0.95).ceil() - 1];
    expect(cold, greaterThan(0));
    expect(p95, greaterThan(0));
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print(
      'SERVICE_SEARCH_BENCHMARK cold_us=$cold warm_median_us=$median '
      'warm_p95_us=$p95 samples=${warm.length} apps=10000 services=2000',
    );
  });
}
