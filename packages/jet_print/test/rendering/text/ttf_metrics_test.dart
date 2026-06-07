// test/rendering/text/ttf_metrics_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/font_format_exception.dart';
import 'package:jet_print/src/rendering/text/font_metrics.dart';
import 'package:jet_print/src/rendering/text/ttf/ttf_metrics.dart';

import '../../support/workspace.dart';

void main() {
  final Directory root = findWorkspaceRoot();
  final Uint8List bytes = File(
    '${root.path}/packages/jet_print/tool/fonts/NotoSans-subset.ttf',
  ).readAsBytesSync();

  test('parses head/hhea/hmtx/cmap of the bundled subset font', () {
    final FontMetrics m = parseTtfMetrics(bytes);
    expect(m.unitsPerEm, 1000);
    expect(m.ascent, 1069);
    expect(m.descent, -293);
    expect(m.lineGap, 0);
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x20)), 260); // space
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x41)), 639); // A
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x4D)), 907); // M
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x2E)), 268); // period
    expect(m.glyphForCodepoint(0x015F), isNonZero); // 'ş' present
    expect(m.glyphForCodepoint(0xFFFF), 0); // unmapped -> .notdef
  });

  test('throws FontFormatException on truncated bytes', () {
    expect(() => parseTtfMetrics(Uint8List.fromList(<int>[0, 1, 0, 0])),
        throwsA(isA<FontFormatException>()));
  });

  test('throws FontFormatException when a table offset runs past the buffer',
      () {
    final int numTables = ByteData.sublistView(bytes).getUint16(4);
    final int dirEnd = 12 + numTables * 16;
    final Uint8List truncated = Uint8List.sublistView(bytes, 0, dirEnd + 4);
    expect(
        () => parseTtfMetrics(truncated), throwsA(isA<FontFormatException>()));
  });
}
