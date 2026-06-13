// Group startNewPage command via the controller (023). Public-API tests
// (no `src/`): the controller dispatches SetGroupStartNewPageCommand internally.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _grouped() => const ReportTemplate(
      name: 'r',
      page: PageFormat.a4Portrait,
      groups: <ReportGroup>[
        ReportGroup(name: 'invoice', expression: r'$F{invoiceNo}'),
      ],
      bands: <ReportBand>[
        ReportBand(type: BandType.groupHeader, height: 20, group: 'invoice'),
        ReportBand(type: BandType.detail, height: 20),
        ReportBand(type: BandType.groupFooter, height: 20, group: 'invoice'),
      ],
    );

ReportGroup _groupNamed(JetReportDesignerController c, String name) =>
    c.template.groups.firstWhere((ReportGroup g) => g.name == name);

void main() {
  test('sets a group to start on a new page, with undo/redo', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _grouped());
    addTearDown(c.dispose);

    expect(_groupNamed(c, 'invoice').startNewPage, isFalse);
    c.setGroupStartNewPage('invoice', true);
    expect(_groupNamed(c, 'invoice').startNewPage, isTrue);
    c.undo();
    expect(_groupNamed(c, 'invoice').startNewPage, isFalse);
    c.redo();
    expect(_groupNamed(c, 'invoice').startNewPage, isTrue);
  });

  test("preserves the group's other fields", () {
    final JetReportDesignerController c = JetReportDesignerController(
      template: const ReportTemplate(
        name: 'r',
        page: PageFormat.a4Portrait,
        groups: <ReportGroup>[
          ReportGroup(
            name: 'g',
            expression: r'$F{k}',
            keepTogether: true,
            reprintHeaderOnEachPage: true,
          ),
        ],
        bands: <ReportBand>[
          ReportBand(type: BandType.groupHeader, height: 10, group: 'g'),
        ],
      ),
    );
    addTearDown(c.dispose);

    c.setGroupStartNewPage('g', true);
    final ReportGroup g = _groupNamed(c, 'g');
    expect(g.startNewPage, isTrue);
    expect(g.keepTogether, isTrue);
    expect(g.reprintHeaderOnEachPage, isTrue);
    expect(g.expression, r'$F{k}');
  });

  test('an unchanged value or unknown group pushes no history (no-op)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _grouped());
    addTearDown(c.dispose);

    c.setGroupStartNewPage('invoice', false); // already false → no-op
    c.setGroupStartNewPage('ghost', true); // unknown group → no-op
    expect(c.canUndo, isFalse);
  });
}
