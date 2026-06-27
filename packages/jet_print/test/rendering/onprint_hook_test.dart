// test/rendering/onprint_hook_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

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
