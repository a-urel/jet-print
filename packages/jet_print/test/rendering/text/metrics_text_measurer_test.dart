// test/rendering/text/metrics_text_measurer_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

import '../../support/workspace.dart';

void main() {
  final FontRegistry reg = FontRegistry()..registerDefault();
  final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
  const JetTextStyle s10 = JetTextStyle(fontSize: 10);
  final Uint8List boldBytes = File('${findWorkspaceRoot().path}'
          '/packages/jet_print/tool/fonts/NotoSans-Bold-subset.ttf')
      .readAsBytesSync();

  test('single line: advance, ascent, line height, size', () {
    final MeasuredText m = measurer.measure('A', s10);
    expect(m.lines, hasLength(1));
    final TextLine l = m.lines.single;
    expect(l.text, 'A');
    expect(l.width, closeTo(6.39, 1e-6)); // 639 * 0.01
    expect(l.top, 0);
    expect(l.baseline, closeTo(10.69, 1e-6)); // 1069 * 0.01
    expect(l.height, closeTo(13.62, 1e-6)); // (1069 + 293) * 0.01
    expect(m.size.width, closeTo(6.39, 1e-6));
    expect(m.size.height, closeTo(13.62, 1e-6));
    expect(m.firstAscent, closeTo(10.69, 1e-6));
  });

  test('hard breaks: each \\n starts a new line; blank lines preserved', () {
    final MeasuredText m = measurer.measure('A\n\nM', s10);
    expect(
        m.lines.map((TextLine l) => l.text).toList(), <String>['A', '', 'M']);
    expect(m.lines[1].width, 0); // blank middle line, full line height
    expect(m.lines[1].top, closeTo(13.62, 1e-6));
    expect(m.lines[2].baseline, closeTo(2 * 13.62 + 10.69, 1e-6));
    expect(m.size.height, closeTo(3 * 13.62, 1e-6));
  });

  test('empty string -> one empty line of full height', () {
    final MeasuredText m = measurer.measure('', s10);
    expect(m.lines.single.text, '');
    expect(m.size.height, closeTo(13.62, 1e-6));
  });

  test('greedy wrap preserves literal whitespace at the break', () {
    // 'M M M' at maxWidth 25: 'M M ' (23.34) fits; adding 'M' (32.41) overflows.
    final MeasuredText m = measurer.measure('M M M', s10, maxWidth: 25);
    expect(m.lines.map((TextLine l) => l.text).toList(), <String>['M M ', 'M']);
    expect(m.lines.first.width, closeTo(23.34, 1e-6)); // 9.07+2.60+9.07+2.60
  });

  test('runs of spaces and leading whitespace are not collapsed', () {
    final MeasuredText m = measurer.measure('  A', s10); // no maxWidth
    expect(m.lines.single.text, '  A');
    expect(m.lines.single.width, closeTo(2 * 2.60 + 6.39, 1e-6));
  });

  test('a tab is measured as a single space', () {
    final MeasuredText tab = measurer.measure('A\tA', s10);
    final MeasuredText spc = measurer.measure('A A', s10);
    expect(tab.lines.single.width, closeTo(spc.lines.single.width, 1e-6));
  });

  test('a word wider than maxWidth gets its own overflowing line', () {
    final MeasuredText m = measurer.measure('MMMM', s10, maxWidth: 5);
    expect(m.lines, hasLength(1));
    expect(m.lines.single.width, closeTo(4 * 9.07, 1e-6));
  });

  test('maxWidth <= 0 yields a single overflowing line per segment', () {
    final MeasuredText m = measurer.measure('A A', s10, maxWidth: 0);
    expect(m.lines, hasLength(1));
    expect(m.lines.single.text, 'A A');
  });

  test('a registered bold variant measures wider than normal (variant-aware)',
      () {
    final FontRegistry r = FontRegistry()
      ..registerDefault()
      ..register(FontRegistry.defaultFamily, boldBytes,
          weight: JetFontWeight.bold);
    final MetricsTextMeasurer m = MetricsTextMeasurer(r);
    final double normal = m.measure('A', s10).lines.single.width;
    final double bold = m
        .measure(
            'A', const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold))
        .lines
        .single
        .width;
    expect(bold, greaterThan(normal)); // 6.90 > 6.39
  });
}
