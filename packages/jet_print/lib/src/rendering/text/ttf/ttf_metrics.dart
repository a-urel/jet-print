// lib/src/rendering/text/ttf/ttf_metrics.dart
/// In-house TTF/OTF **metrics** parser (spec 006): reads head/hhea/maxp/hmtx/cmap
/// only (no glyf/outlines). Pure Dart via [ByteData]. Deterministic.
library;

import 'dart:typed_data';

import '../font_format_exception.dart';
import '../font_metrics.dart';

/// Parses the metric tables of [bytes]. Throws [FontFormatException] on a
/// malformed or unsupported font (including out-of-range table offsets).
FontMetrics parseTtfMetrics(Uint8List bytes) {
  try {
    return _parseMetrics(bytes);
  } on RangeError catch (e) {
    throw FontFormatException('Malformed font (out-of-range access: $e).');
  }
}

FontMetrics _parseMetrics(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FontFormatException('Too short for an offset table.');
  }
  final ByteData d = ByteData.sublistView(bytes);
  final int numTables = d.getUint16(4);

  final Map<String, int> tableOffset = <String, int>{};
  var p = 12;
  for (var i = 0; i < numTables; i++) {
    if (p + 16 > bytes.length) {
      throw const FontFormatException('Truncated table directory.');
    }
    final String tag = String.fromCharCodes(bytes, p, p + 4);
    tableOffset[tag] = d.getUint32(p + 8);
    p += 16;
  }

  int require(String tag) {
    final int? off = tableOffset[tag];
    if (off == null) {
      throw FontFormatException('Missing required "$tag" table.');
    }
    return off;
  }

  // head: unitsPerEm @ +18.
  final int head = require('head');
  final int unitsPerEm = d.getUint16(head + 18);
  if (unitsPerEm == 0) {
    throw const FontFormatException('Invalid unitsPerEm (0).');
  }

  // hhea: ascender @ +4, descender @ +6, lineGap @ +8, numberOfHMetrics @ +34.
  final int hhea = require('hhea');
  final double ascent = d.getInt16(hhea + 4).toDouble();
  final double descent = d.getInt16(hhea + 6).toDouble();
  final double lineGap = d.getInt16(hhea + 8).toDouble();
  final int numberOfHMetrics = d.getUint16(hhea + 34);

  // maxp: numGlyphs @ +4.
  final int numGlyphs = d.getUint16(require('maxp') + 4);

  // hmtx: numberOfHMetrics longHorMetric records (advanceWidth u16, lsb i16).
  final int hmtx = require('hmtx');
  final List<int> advances = List<int>.filled(numGlyphs, 0);
  var lastAdvance = 0;
  for (var g = 0; g < numGlyphs; g++) {
    if (g < numberOfHMetrics) {
      lastAdvance = d.getUint16(hmtx + g * 4);
    }
    advances[g] = lastAdvance; // glyphs past the last record reuse its advance
  }

  // cmap: pick the best Unicode BMP subtable.
  final int cmap = require('cmap');
  final int subCount = d.getUint16(cmap + 2);
  var bestOffset = -1;
  var bestScore = -1;
  var q = cmap + 4;
  for (var i = 0; i < subCount; i++) {
    final int plat = d.getUint16(q);
    final int enc = d.getUint16(q + 2);
    final int off = d.getUint32(q + 4);
    final int score = (plat == 3 && enc == 1)
        ? 3
        : (plat == 0)
            ? 2
            : (plat == 3 && enc == 0)
                ? 1
                : 0;
    if (score > bestScore) {
      bestScore = score;
      bestOffset = cmap + off;
    }
    q += 8;
  }
  if (bestOffset < 0) {
    throw const FontFormatException('No usable cmap subtable.');
  }

  return FontMetrics(
    unitsPerEm: unitsPerEm,
    ascent: ascent,
    descent: descent,
    lineGap: lineGap,
    cmap: _parseCmap(d, bestOffset),
    advanceWidths: advances,
    defaultAdvance: advances.isNotEmpty ? advances[0] : 0,
  );
}

Map<int, int> _parseCmap(ByteData d, int o) {
  final int format = d.getUint16(o);
  switch (format) {
    case 4:
      return _parseCmapFormat4(d, o);
    case 6:
      final int first = d.getUint16(o + 6);
      final int count = d.getUint16(o + 8);
      return <int, int>{
        for (var i = 0; i < count; i++) first + i: d.getUint16(o + 10 + i * 2),
      };
    case 0:
      return <int, int>{
        for (var c = 0; c < 256; c++) c: d.getUint8(o + 6 + c),
      };
    default:
      throw FontFormatException('Unsupported cmap format $format.');
  }
}

Map<int, int> _parseCmapFormat4(ByteData d, int o) {
  final int segX2 = d.getUint16(o + 6);
  final int segCount = segX2 ~/ 2;
  final int endBase = o + 14;
  final int startBase = endBase + segX2 + 2; // +2 reservedPad
  final int deltaBase = startBase + segX2;
  final int rangeBase = deltaBase + segX2;

  final Map<int, int> map = <int, int>{};
  for (var s = 0; s < segCount; s++) {
    final int end = d.getUint16(endBase + s * 2);
    final int start = d.getUint16(startBase + s * 2);
    final int delta = d.getUint16(deltaBase + s * 2);
    final int rangeOffset = d.getUint16(rangeBase + s * 2);
    if (start == 0xFFFF) continue;
    for (var c = start; c <= end; c++) {
      int g;
      if (rangeOffset == 0) {
        g = (c + delta) & 0xFFFF;
      } else {
        final int gi = rangeBase + s * 2 + rangeOffset + (c - start) * 2;
        g = d.getUint16(gi);
        if (g != 0) g = (g + delta) & 0xFFFF;
      }
      if (g != 0) map[c] = g;
    }
  }
  return map;
}
