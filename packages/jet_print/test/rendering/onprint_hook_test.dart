// test/rendering/onprint_hook_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;

ReportDefinition _singleText(String expr) => ReportDefinition(
      name: 'test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(
              Band(
                id: 'detail',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amt',
                    bounds: const JetRect(x: 0, y: 0, width: 120, height: 20),
                    text: 'amt',
                    expression: expr,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

JetInMemoryDataSource _source(num amount) => JetInMemoryDataSource(
      [
        <String, Object?>{'amount': amount}
      ],
      fields: <FieldDef>[FieldDef('amount', type: JetFieldType.double)],
    );

// Collects the colors of the text-run primitives across all pages.
List<JetColor> _textColors(RenderedReport r) => <JetColor>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.pageAt(i).frame.primitives)
          if (p is TextRunPrimitive) p.style.color,
    ];

void main() {
  test('null return suppresses the element', () {
    final ReportDefinition def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (ReportElement el, ElementPrintContext ctx) =>
            el is TextElement ? null : el,
      ),
    );
    final bool hasAmtText = <bool>[
      for (int i = 0; i < r.pageCount; i++)
        for (final FramePrimitive p in r.pageAt(i).frame.primitives)
          if (p is TextRunPrimitive) true,
    ].isNotEmpty;
    expect(hasAmtText, isFalse); // the only text element was suppressed
  });

  test('different-type return is ignored and records a diagnostic', () {
    final ReportDefinition def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (ReportElement el, ElementPrintContext ctx) =>
            el is TextElement
                ? ImageElement(
                    id: el.id,
                    bounds: el.bounds,
                    source: BytesImageSource(Uint8List(0)),
                  )
                : el,
      ),
    );
    // original text still painted
    final List<String> texts = <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final FramePrimitive p in r.pageAt(i).frame.primitives)
          if (p is TextRunPrimitive) p.lines.map((TextLine l) => l.text).join(),
    ];
    expect(texts.join(), contains('7'));
    expect(
      r.diagnostics.entries
          .any((Diagnostic d) => d.message.contains('onElementPrint')),
      isTrue,
    );
  });

  test('a throwing callback is contained: original painted + diagnostic', () {
    final ReportDefinition def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (ReportElement el, ElementPrintContext ctx) =>
            throw StateError('boom'),
      ),
    );
    final List<String> texts = <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final FramePrimitive p in r.pageAt(i).frame.primitives)
          if (p is TextRunPrimitive) p.lines.map((TextLine l) => l.text).join(),
    ];
    expect(texts.join(), contains('7'));
    expect(
      r.diagnostics.entries
          .any((Diagnostic d) => d.message.contains('onElementPrint')),
      isTrue,
    );
  });

  test('null callback passes through; transform recolors a text element', () {
    final def = _singleText(r'$F{amount}');

    final RenderedReport plain =
        const JetReportEngine().renderDefinition(def, _source(-5));
    expect(_textColors(plain), everyElement(JetColor.black));

    final RenderedReport painted = const JetReportEngine().renderDefinition(
      def,
      _source(-5),
      options: RenderOptions(
        onElementPrint: (ReportElement el, ElementPrintContext ctx) {
          if (el is! TextElement) return el;
          final v = ctx.fields['amount'];
          if (v is JetNumber && v.value < 0) {
            return el.copyWith(
                style: el.style.copyWith(color: const JetColor(0xFFFF0000)));
          }
          return el;
        },
      ),
    );
    expect(_textColors(painted), contains(const JetColor(0xFFFF0000)));
  });
}
