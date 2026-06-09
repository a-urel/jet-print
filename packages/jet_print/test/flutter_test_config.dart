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
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

/// Maximum fraction of differing pixels treated as a pass (0.005 == 0.5%).
///
/// The observed cross-host delta is ≈0.0002% (a literal handful of edge
/// pixels); 0.5% leaves a large safety margin for runner-image drift while
/// staying far below any meaningful visual regression.
const double _goldenTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The framework has already set a per-test-file `LocalFileComparator` whose
  // `basedir` points at the running test's directory (so relative golden paths
  // resolve correctly). Wrap it, preserving that basedir.
  final GoldenFileComparator previous = goldenFileComparator;
  if (previous is LocalFileComparator) {
    goldenFileComparator =
        _TolerantGoldenComparator(previous.basedir, _goldenTolerance);
  }
  await testMain();
}

/// A [LocalFileComparator] that accepts a sub-threshold pixel difference.
class _TolerantGoldenComparator extends LocalFileComparator {
  // `LocalFileComparator` derives its `basedir` from the *file* part of the
  // given URI; [basedir] already ends in '/', so resolving any filename against
  // it yields the same directory back.
  _TolerantGoldenComparator(Uri basedir, this.tolerance)
      : super(basedir.resolve('flutter_test_config.dart'));

  /// Maximum differing-pixel fraction (0..1) treated as a pass.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      return true;
    }
    // Over tolerance: write the diff artifacts and fail loudly, exactly as the
    // default comparator would, so a genuine regression is just as visible.
    final String error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
