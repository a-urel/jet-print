// Binding persistence + reopen-without-source (US2 / FR-019, FR-019a).
//
// Bindings are self-describing (TextElement.expression / FieldImageSource), so
// they round-trip losslessly and a report reopened with NO data source attached
// still carries them (tokens render on the canvas) while the structure tree
// shows its empty state. Public API only (no `src/`).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

/// A one-band template with a bound text element and a bound image element.
ReportTemplate _boundTemplate() => const ReportTemplate(
      name: 'r',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 120,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 10, y: 10, width: 120, height: 18),
              text: 'customerName',
              expression: r'$F{customerName}',
            ),
            ImageElement(
              id: 'i1',
              bounds: JetRect(x: 10, y: 40, width: 80, height: 40),
              source: FieldImageSource('logo'),
            ),
          ],
        ),
      ],
    );

void main() {
  test('text + image bindings round-trip losslessly through the file format',
      () {
    final ReportTemplate template = _boundTemplate();
    final String json = JetReportFormat.encodeJson(template);
    final ReportTemplate decoded = JetReportFormat.decodeJson(json);

    // Stable: re-encoding the decoded template reproduces the same JSON.
    expect(JetReportFormat.encodeJson(decoded),
        JetReportFormat.encodeJson(template));

    final TextElement t =
        decoded.bands.single.elements.whereType<TextElement>().single;
    expect(t.expression, r'$F{customerName}');
    final ImageElement i =
        decoded.bands.single.elements.whereType<ImageElement>().single;
    expect(i.source, isA<FieldImageSource>());
    expect((i.source as FieldImageSource).field, 'logo');
  });

  testWidgets(
      'reopened without a source: bindings persist, structure tree is empty',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _boundTemplate());
    addTearDown(c.dispose);

    // Attach NO dataSchema (as if reopened on a fresh session).
    await pumpDesigner(tester, designer: JetReportDesigner(controller: c));

    // The structure tree shows its empty state (FR-019a).
    expect(find.text('No data source attached.'), findsOneWidget);
    // The binding is preserved (the token is painted on the canvas; assert the
    // self-describing model rather than the painted pixels).
    final TextElement t =
        c.template.bands.single.elements.whereType<TextElement>().single;
    expect(t.expression, r'$F{customerName}');
  });
}
