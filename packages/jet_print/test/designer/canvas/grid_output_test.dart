// Grid is absent from preview/export output (spec 015, US4 / contract C6.1 /
// FR-016, SC-005; Constitution IV — WYSIWYG).
//
// Black-box: imports only the public entry point. The preview/export path
// renders the report MODEL through JetReportEngine → JetReportExporter; the grid
// is design-time canvas chrome that never enters that pipeline. This pins that
// the rendered/exported page is byte-identical whether the grid (and snap) is on
// or off — so a visible grid can never leak into output. The existing invoice
// preview/export goldens (rendered through the same path) remain unchanged.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _template() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat(width: 200, height: 120, margins: JetEdgeInsets.all(10)),
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
            ShapeElement(
              id: 'rule',
              bounds: JetRect(x: 0, y: 24, width: 180, height: 0),
              kind: ShapeKind.line,
              style: JetBoxStyle(stroke: JetColor.black),
            ),
          ],
        ),
      ],
    );

JetInMemoryDataSource _data() => JetInMemoryDataSource(
      <Map<String, Object?>>[
        <String, Object?>{'name': 'Acme'},
        <String, Object?>{'name': 'Globex'},
      ],
    );

Future<Uint8List> _exportFirstPage(JetReportDesignerController c) async {
  const JetReportExporter exporter = JetReportExporter();
  // Render exactly what a host saves (c.template) through the public engine.
  final RenderedReport report =
      const JetReportEngine().render(c.template, _data());
  return exporter.pageToPng(report, 0, scale: 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C6.1 exported page bytes are identical with the grid on vs off',
      () async {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _template());
    addTearDown(c.dispose);

    // Grid + snap on (defaults).
    expect(c.gridEnabled, isTrue);
    final Uint8List withGrid = await _exportFirstPage(c);

    // Hide the grid and disable snapping — the rendered output must not move.
    c.setGridEnabled(false);
    c.setSnapEnabled(false);
    final Uint8List withoutGrid = await _exportFirstPage(c);

    expect(withoutGrid, equals(withGrid),
        reason:
            'the grid is design-time chrome — it must leave no trace in the '
            'exported page (true WYSIWYG)');
  });

  test('toggling the grid does not mutate the saved report model', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _template());
    addTearDown(c.dispose);

    final Map<String, Object?> before = JetReportFormat.encode(c.template);
    c.setGridEnabled(false);
    c.setSnapEnabled(false);
    final Map<String, Object?> after = JetReportFormat.encode(c.template);

    expect(after, equals(before),
        reason: 'grid/snap are ephemeral view state, never in the model');
  });
}
