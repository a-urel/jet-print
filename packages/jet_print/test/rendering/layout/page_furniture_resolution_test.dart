// Page header/footer elements honor the same `visible` and `format` an element
// in a body band does.
//
// Regression: the layouter placed every page-furniture element as authored —
// `visible` was never evaluated (a hidden header logo printed on every page)
// and a chrome text's `format` was dropped when its expression was substituted
// per page (a formatted footer printed the raw value).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// 200x100 page, 10pt margins: content top=10, bottom=90.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const JetRect _chromeBounds = JetRect(x: 0, y: 0, width: 180, height: 20);

ReportDefinition _tpl({Band? header, Band? footer}) => ReportDefinition(
      name: 'furniture',
      page: _page,
      furniture: PageFurniture(pageHeader: header, pageFooter: footer),
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

Band _header(List<ReportElement> elements,
        {BoolProperty visible = const BoolProperty()}) =>
    Band(
        id: 'ph',
        type: BandType.pageHeader,
        height: 20,
        elements: elements,
        visible: visible);

Band _footer(List<ReportElement> elements) =>
    Band(id: 'pf', type: BandType.pageFooter, height: 20, elements: elements);

ShapeElement _logo({BoolProperty visible = const BoolProperty()}) =>
    ShapeElement(
        id: 'logo',
        bounds: _chromeBounds,
        kind: ShapeKind.rectangle,
        visible: visible);

FilledBand _body(String id, double height) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: <ReportElement>[
        ShapeElement(
            id: id,
            bounds: JetRect(x: 0, y: 0, width: 180, height: height),
            kind: ShapeKind.rectangle),
      ],
      variables: const <String, JetValue>{},
    );

// header 20 + footer 20 leave a 40pt body: two 40pt rows -> two pages.
LayoutResult _layout(ReportDefinition tpl, {int rows = 2}) =>
    ReportLayouter().layoutDefinition(
        tpl,
        FilledReport(page: _page, bands: <FilledBand>[
          for (int i = 0; i < rows; i++) _body('row$i', 40),
        ]));

bool _drawn(PageFrame page, String id) =>
    page.primitives.any((FramePrimitive p) => p.elementId == id);

double _y(PageFrame page, String id) => page.primitives
    .firstWhere((FramePrimitive p) => p.elementId == id)
    .bounds
    .y;

String _text(PageFrame page, String id) => page.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .lines
    .map((TextLine l) => l.text)
    .join();

void main() {
  group('visible', () {
    test('a hidden header element is not drawn on any page', () {
      final LayoutResult r = _layout(_tpl(
          header: _header(<ReportElement>[
        _logo(visible: const BoolProperty(value: false)),
      ])));
      expect(r.pages, hasLength(2));
      for (final PageFrame page in r.pages) {
        expect(_drawn(page, 'logo'), isFalse);
      }
    });

    test('a visibility expression is evaluated per page, with page variables',
        () {
      final LayoutResult r = _layout(_tpl(
          footer: _footer(<ReportElement>[
        _logo(
            visible: const BoolProperty(expression: r'$V{PAGE_NUMBER} == "1"')),
      ])));
      expect(_drawn(r.pages[0], 'logo'), isTrue);
      expect(_drawn(r.pages[1], 'logo'), isFalse);
    });

    test('a hidden header band draws nothing but keeps its space', () {
      final LayoutResult r = _layout(_tpl(
          header: _header(<ReportElement>[_logo()],
              visible: const BoolProperty(value: false))));
      expect(_drawn(r.pages.first, 'logo'), isFalse);
      // The body still starts below the reserved header: top 10 + header 20.
      expect(_y(r.pages.first, 'row0'), 30);
    });

    test('a broken expression keeps the element and is diagnosed once', () {
      final LayoutResult r = _layout(_tpl(
          header: _header(<ReportElement>[
        _logo(visible: const BoolProperty(expression: '1 +')),
      ])));
      for (final PageFrame page in r.pages) {
        expect(_drawn(page, 'logo'), isTrue);
      }
      expect(
          r.diagnostics.entries
              .where((Diagnostic d) =>
                  d.severity == DiagnosticSeverity.error &&
                  d.elementId == 'logo')
              .length,
          1);
    });
  });

  // Review finding on #65: a page context resolves fields and non-page
  // variables to null, so `$F{flag} == true` evaluated to a clean false and
  // hid the object silently instead of failing safe.
  group('references unavailable at page scope', () {
    for (final String expression in <String>[
      r'$F{flag} == true',
      r'$V{total} == 0',
    ]) {
      test('$expression keeps the object visible and is diagnosed once', () {
        final LayoutResult r = _layout(_tpl(
            header: _header(<ReportElement>[
          _logo(visible: BoolProperty(expression: expression)),
        ])));
        for (final PageFrame page in r.pages) {
          expect(_drawn(page, 'logo'), isTrue);
        }
        expect(
            r.diagnostics.entries
                .where((Diagnostic d) => d.elementId == 'logo')
                .length,
            1);
      });
    }
  });

  group('format', () {
    test('a chrome text expression applies the element format', () {
      final LayoutResult r = _layout(
          _tpl(
              footer: _footer(const <ReportElement>[
            TextElement(
                id: 'total',
                bounds: _chromeBounds,
                text: '',
                expression: '1234.5',
                format: '#,##0.00'),
          ])),
          rows: 1);
      expect(_text(r.pages.single, 'total'), '1,234.50');
    });
  });
}
