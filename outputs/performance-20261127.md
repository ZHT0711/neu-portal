# NEUPortal performance check — 2026-11-27

## Scope

This pass targets service-catalog search work, catalog-cache correctness, and duplicate homepage agenda derivation. It does **not** claim that all app performance opportunities are exhausted, nor that synthetic widget-runner timings represent physical phones.

## Changes under test

- `lib/pages/services_page.dart` caches category counts by catalog snapshot and normalized app/service search names. App descriptions are lowercased lazily and once per indexed app, and service matches are grouped by section position so repeated references preserve their original per-section results.
- `lib/core/app_state.dart` snapshots app catalogs and service sections/entries as unmodifiable lists on assignment. This makes the identity-based UI indexes safe against caller mutation; catalog replacement creates a new snapshot and rebuilds indexes.
- The search sliver has a stable key, preventing the search editor from being discarded when query-dependent slivers appear or disappear. Non-empty queries are applied after an 80ms trailing debounce to coalesce rapid typing; clearing remains immediate.
- `lib/pages/home_page.dart` derives the agenda once from the same captured `DateTime`; the “next” item is selected from that list rather than calculating and sorting the agenda a second time.
- Automatic idle tab preparation remains in place: existing first-switch tests explicitly require prepared tabs and this pass did not establish a device-level trade-off that justifies changing it.

## Verification

- `flutter test --no-pub`: **160 tests passed** (including the standalone diagnostic benchmark added below).
- `flutter test test/performance_regression_test.dart --no-pub --reporter expanded`: **22 tests passed** on Android and iOS widget configurations, including visible-grid bounds, search focus retention, rapid-edit debounce and immediate clearing, repeated service-section results, cache refresh on catalog replacement, and tab-return state.
- `flutter test test/performance_benchmark_test.dart --no-pub --reporter expanded`: passed; 10,000 synthetic apps and 2,000 synthetic services.
- `flutter analyze --no-pub`: **No issues found**.
- `node tools/test_portal_document.mjs`, `node tools/test_learning_bridges.mjs`, `python tools/test_verify_ipa.py`: passed (IPA suite: 7 tests).
- `flutter build web --release --no-pub`: passed. Flutter's optional Wasm dry run still reports the existing `flutter_secure_storage_web` dependency on `dart:html` / `dart:js_util`; the JavaScript release build completes.
- Android SDK and Xcode are not installed in this environment; native release builds need CI or suitable toolchains.

## Reproducible diagnostic benchmark

Run:

```powershell
D:/flutter/bin/flutter.bat test test/performance_benchmark_test.dart --no-pub --reporter expanded --concurrency=1
```

The exact same benchmark file was run in three sequential candidate/baseline pairs. The baseline used a detached worktree at `943da1dec62d97f416472697a6012232d63287c7`; both used Flutter 3.47.8 / Dart 3.13.7. Each run exercised 10,000 apps, 2,000 services and 25 warm nonmatching queries; the table shows medians across the three runs.

| Measurement | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Cold query | 96,239 µs | 103,690 µs | 7.7% slower |
| Warm median | 23,437 µs | 20,046 µs | 14.5% faster |
| Warm p95 | 35,458 µs | 30,469 µs | 14.1% faster |

This exposes a real trade-off: building the cache costs more on the first query, while repeated queries improve. The experiment is synthetic and limited to a widget-test runner; no phone-level speedup is claimed. Values are diagnostic, not CI thresholds.

The benchmark invokes the same search callback and pumps 100ms of test-clock time per sample, enough for the candidate's 80ms debounce timer. The pump duration is virtual, not 100ms of elapsed wall time; measured values reflect test-runner callback/frame processing. The baseline performs immediate filtering and does not have the debounce. Re-run on a fixed machine/runtime before comparing revisions.

## Known remaining measurement gaps

- No physical Android/iOS frame, startup, thermal, or memory profile was available in this environment.
- The benchmark is a repeatable widget-runner diagnostic, not an end-user device benchmark. The cold path is substantially more expensive than warm queries and remains a candidate for device-level profiling before further algorithm changes. Non-empty search results may lag the last keystroke by up to 80ms; this change coalesces rapid edits but does not remove the cold scan cost.
- Broad `AppScope` notification fan-out and tab-warmup trade-offs remain unmeasured; no claims are made that these or every other optimization opportunity have been exhausted.
