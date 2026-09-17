// A failing golden must FAIL the test — even outside `testWidgets`.
//
// `matchesGoldenFile` routes an image (or a Finder) through
// `TestWidgetsFlutterBinding.runAsync`, whose `catchError` reports the
// exception to `FlutterError` and then completes the future with `null`.
// `AsyncMatcher` reads `null` as "matched". Inside `testWidgets` the reported
// error still fails the test, because `runTest` installs a collector on
// `FlutterError.onError`; inside a plain `test()` nothing collects it, so a
// comparator that throws anything other than a `TestFailure` is swallowed
// whole. The run goes green and the only trace is a `failures/` directory
// filling up on a passing run.
//
// Seven golden pins in this package sit in plain `test()` bodies
// (`rendering/export/png_export_test.dart`, `rendering/paint/*_golden_test.dart`,
// `rendering/chart_golden_test.dart`). They were vacuous until the tolerant
// comparator in `test/support/golden_config_io.dart` started throwing
// `TestFailure`, which `MatchesGoldenFile.matchAsync` catches and turns into a
// real mismatch message. This guard pins that, and pins the failure feedback
// `AGENTS.md` tells contributors to look at first.
//
// The mismatch here is a size mismatch, so the comparison is host-independent:
// no glyph rasterization is involved, only the plumbing.
@Tags(<String>['golden'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

Future<ui.Image> _opaqueImage(int width, int height) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(List<int>.filled(width * height * 4, 0xFF)),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a golden mismatch inside a plain test() is not swallowed', () async {
    // Anchored on the workspace root, never on `Directory.current`: the
    // documented gate runs from the workspace root while `flutter test` inside
    // the package runs from the package, so a relative path resolves to two
    // different places. `LocalFileComparator.basedir` is the more direct
    // anchor, but web's `flutter_test` exports a `LocalFileComparator` with no
    // such getter, and the Chrome leg type-checks every test file before
    // `@TestOn` or `--exclude-tags` can exclude one.
    final Directory failures = Directory(
        '${findWorkspaceRoot().path}/packages/jet_print/test/architecture/failures');
    addTearDown(() {
      if (failures.existsSync()) {
        failures.deleteSync(recursive: true);
      }
    });

    // 4x4 against the 800x600 invoice pin: a mismatch no tolerance absorbs.
    final ui.Image image = await _opaqueImage(4, 4);
    addTearDown(image.dispose);

    await expectLater(
      expectLater(image, matchesGoldenFile('../goldens/invoice_page1_2x.png')),
      throwsA(
        isA<TestFailure>().having(
          (TestFailure e) => e.message,
          'message',
          contains('invoice_page1_2x.png'),
        ),
      ),
      reason:
          'a mismatch must fail the test, not report to a sink nobody reads',
    );

    // The failure feedback AGENTS.md sends contributors to.
    expect(
      failures
          .listSync()
          .map((FileSystemEntity e) => e.uri.pathSegments.last)
          .toSet(),
      <String>{
        'invoice_page1_2x_masterImage.png',
        'invoice_page1_2x_testImage.png',
      },
      reason: 'a real failure writes images to look at before regenerating',
    );
  });
}
