// Explicit per-render locale (011 — contract C7 / FR-012a).
//
// Number/date formatting follows `RenderOptions.locale` — never the ambient
// `Intl.defaultLocale` — so the same template + data rendered under two
// locales differ only in locale-sensitive formatting.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const PageFormat _page =
    PageFormat(width: 400, height: 200, margins: JetEdgeInsets.all(10));

ReportTemplate _template(String expression) => ReportTemplate(
      name: 'locale',
      page: _page,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 24,
          elements: <ReportElement>[
            TextElement(
              id: 'value',
              bounds: const JetRect(x: 0, y: 0, width: 360, height: 18),
              text: 'value',
              expression: expression,
            ),
          ],
        ),
      ],
    );

String _renderedText(
  String expression,
  Map<String, Object?> row, {
  required Locale locale,
}) {
  final RenderedReport report = const JetReportEngine().render(
    _template(expression),
    JetInMemoryDataSource(<Map<String, Object?>>[row]),
    options: RenderOptions(locale: locale),
  );
  final PageFrame frame = report.pageAt(0).frame;
  return frame.primitives
      .whereType<TextRunPrimitive>()
      .firstWhere((TextRunPrimitive p) => p.elementId == 'value')
      .lines
      .map((TextLine l) => l.text)
      .join();
}

void main() {
  setUpAll(initializeDateFormatting);

  tearDown(() {
    Intl.defaultLocale = null;
  });

  const String numberExpr = r'FORMAT($F{amount}, "#,##0.00")';
  final Map<String, Object?> numberRow = <String, Object?>{'amount': 1234.5};

  test('number formatting follows the render locale', () {
    expect(_renderedText(numberExpr, numberRow, locale: const Locale('en')),
        '1,234.50');
    expect(_renderedText(numberExpr, numberRow, locale: const Locale('de')),
        '1.234,50');
    expect(_renderedText(numberExpr, numberRow, locale: const Locale('tr')),
        '1.234,50');
  });

  test('date formatting follows the render locale', () {
    const String dateExpr = r'FORMAT($F{when}, "MMMM")';
    final Map<String, Object?> row = <String, Object?>{
      'when': DateTime(2026, 1, 15),
    };
    expect(_renderedText(dateExpr, row, locale: const Locale('en')),
        'January');
    expect(
        _renderedText(dateExpr, row, locale: const Locale('de')), 'Januar');
    expect(_renderedText(dateExpr, row, locale: const Locale('tr')), 'Ocak');
  });

  test('formatting is independent of the ambient Intl.defaultLocale', () {
    Intl.defaultLocale = 'de';
    expect(
      _renderedText(numberExpr, numberRow, locale: const Locale('en')),
      '1,234.50',
      reason: 'the explicit render locale must win over the ambient default',
    );
    Intl.defaultLocale = 'en_US';
    expect(
      _renderedText(numberExpr, numberRow, locale: const Locale('de')),
      '1.234,50',
    );
  });

  test('the same inputs under two locales differ only in formatting', () {
    final String en =
        _renderedText(numberExpr, numberRow, locale: const Locale('en'));
    final String de =
        _renderedText(numberExpr, numberRow, locale: const Locale('de'));
    expect(en, isNot(de));
    // Same digits, different separators — the value itself is unchanged.
    String digitsOf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
    expect(digitsOf(en), digitsOf(de));
  });
}
