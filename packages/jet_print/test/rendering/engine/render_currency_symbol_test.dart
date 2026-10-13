// RenderOptions.currencySymbol: what `¤` prints in a number pattern.
//
// Left null — the default — `¤` prints the ISO 4217 code of the render
// locale's currency, exactly as before (`TRY1.234,50`): after 1.0 a default
// is part of the output contract (decision 0004), so the symbol is opt-in.
// Set, `¤` prints the symbol instead, in the format property and in FORMAT()
// alike, while every other part of the pattern — its decimal digits included —
// keeps its meaning.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const PageFormat _page =
    PageFormat(width: 400, height: 200, margins: JetEdgeInsets.all(10));

/// One detail text element showing `$F{amount}`, either through the format
/// property ([format]) or through an [expression] of its own; plus a page
/// footer formatting the `total` parameter, which is evaluated only when a
/// page is built, after renderDefinition has returned.
ReportDefinition _template({String? format, String? expression}) =>
    ReportDefinition(
      name: 'currency',
      page: _page,
      parameters: const <ReportParameter>[
        ReportParameter(name: 'total', type: JetFieldType.double),
      ],
      furniture: const PageFurniture(
        pageFooter: Band(
          id: 'pf',
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'footer',
              bounds: JetRect(x: 0, y: 0, width: 360, height: 18),
              text: '',
              expression: r'FORMAT($P{total}, "¤#,##0.00")',
            ),
          ],
        ),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 24,
              elements: <ReportElement>[
                TextElement(
                  id: 'value',
                  bounds: const JetRect(x: 0, y: 0, width: 360, height: 18),
                  text: '',
                  expression: expression ?? r'$F{amount}',
                  format: format,
                ),
              ],
            )),
          ],
        ),
      ),
    );

String _text(PageFrame frame, String id) => frame.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .lines
    .map((TextLine l) => l.text)
    .join();

PageFrame _render(
  ReportDefinition def, {
  double amount = 1234.5,
  String? symbol,
}) {
  final RenderedReport report = const JetReportEngine().renderDefinition(
    def,
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'amount': amount},
    ]),
    options: RenderOptions(
      locale: const Locale('tr'),
      parameters: const <String, Object?>{'total': 99.9},
      currencySymbol: symbol,
    ),
  );
  return frameOf(report.pageAt(0));
}

String _value(String format, {double amount = 1234.5, String? symbol}) => _text(
    _render(_template(format: format), amount: amount, symbol: symbol),
    'value');

void main() {
  test('by default ¤ prints the ISO code, exactly as before', () {
    expect(_value('¤#,##0.00'), 'TRY1.234,50');
  });

  test('a currency symbol replaces the code in the format property', () {
    expect(_value('¤#,##0.00', symbol: '₺'), '₺1.234,50');
    expect(_value('#,##0.00 ¤', symbol: '₺'), '1.234,50 ₺');
  });

  test('the pattern still decides the decimal digits', () {
    expect(_value('#,##0 ¤', symbol: '₺'), '1.235 ₺');
    expect(_value('#,##0.## ¤', symbol: '₺'), '1.234,5 ₺');
    expect(_value('#,##0.000 ¤', symbol: '₺'), '1.234,500 ₺');
  });

  test('a negative subpattern and a zero total keep their rules', () {
    expect(_value('¤#,##0.00;(¤#,##0.00)', amount: -5, symbol: '₺'), '(₺5,00)');
    expect(_value('¤#,##0.00', amount: -0.001, symbol: '₺'), '₺0,00',
        reason: 'a value that formats as zero prints unsigned (#95)');
  });

  test('a pattern without ¤ is unaffected by the symbol', () {
    expect(_value('#,##0.00', symbol: '₺'), _value('#,##0.00'));
  });

  test('FORMAT() uses the symbol too, the same as the property', () {
    final PageFrame frame = _render(
        _template(expression: r'FORMAT($F{amount}, "¤#,##0.00")'),
        symbol: '₺');
    expect(_text(frame, 'value'), '₺1.234,50');
  });

  test('page chrome formatted when a page is built uses it as well', () {
    expect(
        _text(_render(_template(format: ''), symbol: '₺'), 'footer'), '₺99,90');
    expect(_text(_render(_template(format: '')), 'footer'), 'TRY99,90');
  });
}
