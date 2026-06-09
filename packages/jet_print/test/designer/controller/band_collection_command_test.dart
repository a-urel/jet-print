// Band collection-binding command + band-path addressing (US3 / FR-015,
// FR-015a). Public-API controller tests (no `src/`).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _nested() => const ReportTemplate(
      name: 'r',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 100,
          children: <ReportBand>[ReportBand(type: BandType.detail, height: 40)],
        ),
      ],
    );

void main() {
  test('designates a top-level band as collection-bound, with undo/redo', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _nested());
    addTearDown(c.dispose);

    c.setBandCollection(<int>[0], 'lines');
    expect(c.template.bands[0].collectionField, 'lines');
    c.undo();
    expect(c.template.bands[0].collectionField, isNull);
    c.redo();
    expect(c.template.bands[0].collectionField, 'lines');
  });

  test('addresses a nested band by path, leaving the parent untouched', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _nested());
    addTearDown(c.dispose);

    c.setBandCollection(<int>[0, 0], 'subLines');
    expect(c.template.bands[0].children[0].collectionField, 'subLines');
    expect(c.template.bands[0].collectionField, isNull);
  });

  test('clearing reverts to master scope; a no-op pushes no history', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _nested());
    addTearDown(c.dispose);

    c.setBandCollection(<int>[0], 'lines');
    c.setBandCollection(<int>[0], 'lines'); // no-op (unchanged)
    c.setBandCollection(<int>[0], null); // clear
    expect(c.template.bands[0].collectionField, isNull);

    c.undo(); // undo the clear → 'lines'
    expect(c.template.bands[0].collectionField, 'lines');
    c.undo(); // undo the set → null (the no-op added no entry)
    expect(c.template.bands[0].collectionField, isNull);
  });
}
