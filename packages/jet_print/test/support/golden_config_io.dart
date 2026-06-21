// VM (dart:io) implementation of the tolerant golden comparator setup.
// Imported by flutter_test_config.dart via conditional import.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

const double _goldenTolerance = 0.005;

Future<void> setupGoldenComparator() async {
  final GoldenFileComparator previous = goldenFileComparator;
  if (previous is LocalFileComparator) {
    goldenFileComparator =
        _TolerantGoldenComparator(previous.basedir, _goldenTolerance);
  }
}

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(Uri basedir, this.tolerance)
      : super(basedir.resolve('flutter_test_config.dart'));

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
    final String error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
