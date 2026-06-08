// BandMeasurer: grow-only, height-only band measurement (spec 008a §5).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/layout/band_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

/// Deterministic measurer: block height = 10 * (number of '\n'-separated lines),
/// so layout growth is exact and font-independent. Width is `maxWidth ?? 0`.
class _FixedMeasurer implements TextMeasurer {
  const _FixedMeasurer();
  @override
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth}) {
    final List<String> segs = text.split('\n');
    final List<TextLine> lines = <TextLine>[
      for (int i = 0; i < segs.length; i++)
        TextLine(
            text: segs[i],
            width: 0,
            top: i * 10.0,
            baseline: i * 10.0,
            height: 10),
    ];
    return MeasuredText(
      lines: lines,
      size: JetSize(maxWidth ?? 0, segs.length * 10.0),
      firstAscent: 10,
      fontFamily: 'Fake',
    );
  }
}

BandMeasurer _measurer() {
  final ElementTypeRegistry reg = ElementTypeRegistry();
  registerBuiltInElementTypes(reg);
  return BandMeasurer(
      reg.renderers, const RenderContext(measurer: _FixedMeasurer()));
}

FilledBand _band(double height, List<ReportElement> elements) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: elements,
      variables: const <String, JetValue>{},
    );

TextElement _text(String id, JetRect bounds, String text) =>
    TextElement(id: id, bounds: bounds, text: text);

void main() {
  test('a band with no elements measures to its designed height', () {
    final MeasuredBand mb =
        _measurer().measure(_band(40, const <ReportElement>[]));
    expect(mb.height, 40);
    expect(mb.elements, isEmpty);
  });

  test('an element shorter than its box does not shrink it (grow-only)', () {
    // 1 line -> measured 10; bounds height 20 -> box stays 20; designed 50 wins.
    final MeasuredBand mb = _measurer().measure(_band(50, <ReportElement>[
      _text('t', const JetRect(x: 0, y: 0, width: 100, height: 20), 'one'),
    ]));
    expect(mb.elements.single.bounds.height, 20);
    expect(mb.height, 50);
  });

  test('a tall element grows its box and the band to the element bottom', () {
    // 3 lines -> measured 30; bounds height 10 -> box grows to 30; band -> 30.
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('t', const JetRect(x: 0, y: 0, width: 100, height: 10), 'a\nb\nc'),
    ]));
    expect(mb.elements.single.bounds.height, 30);
    expect(mb.elements.single.bounds.width, 100); // width unchanged
    expect(mb.height, 30);
  });

  test('band height is the maximum element bottom', () {
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('a', const JetRect(x: 0, y: 0, width: 100, height: 10), 'x'),
      _text('b', const JetRect(x: 0, y: 50, width: 100, height: 10), 'p\nq'),
    ]));
    // 'b' at y=50, 2 lines -> 20 tall -> bottom 70.
    expect(mb.height, 70);
  });

  test('a growing element does not move its siblings (no reflow)', () {
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('top', const JetRect(x: 0, y: 0, width: 100, height: 10), 'a\nb\nc'),
      _text('below', const JetRect(x: 0, y: 5, width: 100, height: 10), 'z'),
    ]));
    final JetRect below = mb.elements
        .firstWhere((({ReportElement element, JetRect bounds}) e) =>
            e.element.id == 'below')
        .bounds;
    expect(below.y, 5); // keeps its authored y even though 'top' grew to 30
  });
}
