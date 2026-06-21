// Test bootstrap for `packages/jet_print` — installs a golden comparator that
// tolerates cross-host anti-aliasing noise.
//
// Why: the design-surface goldens (`test/designer/goldens/*.png`) are rasterized
// once on a developer's macOS host and committed. CI runs the SAME Flutter
// version (3.44.0, pinned in `.github/workflows/ci.yml`) but on GitHub's
// `macos-latest` runner, whose CoreText glyph rasterization differs by a sub-
// pixel amount on text edges. The default exact-match comparator rejects any
// non-zero delta, so the text-heavy surface goldens fail CI with "0.00%, 1px
// diff" even though nothing about the render changed.
//
// This comparator passes when the differing-pixel fraction is below a small
// threshold, so host AA noise no longer fails the suite while a real visual
// regression — which is orders of magnitude larger than the threshold — still
// does. `flutter test` auto-discovers this file by walking up from each test.
//
// On Chrome the golden tests are excluded via --exclude-tags golden, so the
// comparator is a no-op (golden_config_web.dart stub).
import 'dart:async';

// flutter_test is imported via the conditional golden_config files below,
// but we still need FutureOr from dart:async here.

import 'support/golden_config_io.dart'
    if (dart.library.js_interop) 'support/golden_config_web.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The framework has already set a per-test-file `LocalFileComparator` whose
  // `basedir` points at the running test's directory (so relative golden paths
  // resolve correctly). Wrap it, preserving that basedir.
  await setupGoldenComparator();
  await testMain();
}
