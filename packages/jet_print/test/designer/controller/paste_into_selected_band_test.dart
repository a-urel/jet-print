// Paste-into-selected-band redirect (single-source clipboard + band selected).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

// Two-band fixture: a 'header' band (one element) and a 'detail' band (two).
ReportDefinition _fixture() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'header',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'h1',
                    bounds: JetRect(x: 10, y: 10, width: 20, height: 10),
                    text: 'h1'),
              ],
            )),
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'd1',
                    bounds: JetRect(x: 50, y: 60, width: 20, height: 10),
                    text: 'd1'),
                TextElement(
                    id: 'd2',
                    bounds: JetRect(x: 80, y: 90, width: 20, height: 10),
                    text: 'd2'),
              ],
            )),
          ],
        ),
      ),
    );

Band _band(JetReportDesignerController c, String id) => c.definition.body.root
    .children
    .whereType<BandNode>()
    .firstWhere((BandNode n) => n.band.id == id)
    .band;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('single-source clipboard + foreign band selected pastes into that band '
      'at original X/Y', () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.selectBand('header');
    c.paste();

    // Copy lands in the selected (header) band, not back in detail.
    expect(_band(c, 'header').elements.length, 2);
    expect(_band(c, 'detail').elements.length, 2);

    final String newId = c.selection.singleOrNull!;
    final ReportElement pasted = _band(c, 'header')
        .elements
        .firstWhere((ReportElement e) => e.id == newId);
    // Original X/Y preserved (no +8/+8 across bands).
    expect(pasted.bounds.x, 50);
    expect(pasted.bounds.y, 60);
    c.dispose();
  });

  test('multi-element single-source clipboard all land in the selected band',
      () {
    final JetReportDesignerController c = _open()
      ..select('d1')
      ..addToSelection('d2');
    c.copy();
    c.selectBand('header');
    c.paste();

    expect(_band(c, 'header').elements.length, 3); // h1 + two copies
    expect(_band(c, 'detail').elements.length, 2); // originals untouched
    expect(c.selection.length, 2); // the two copies are selected
    c.dispose();
  });

  test('same band selected keeps the +8/+8 offset', () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.selectBand('detail'); // selected == source band
    c.paste();

    expect(_band(c, 'detail').elements.length, 3);
    final String newId = c.selection.singleOrNull!;
    final ReportElement pasted = _band(c, 'detail')
        .elements
        .firstWhere((ReportElement e) => e.id == newId);
    expect(pasted.bounds.x, 58); // 50 + 8
    expect(pasted.bounds.y, 68); // 60 + 8
    c.dispose();
  });

  test('no band selected keeps per-source-band paste (+8/+8 in source band)',
      () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.clearSelection();
    c.paste();

    expect(_band(c, 'detail').elements.length, 3); // back in source band
    expect(_band(c, 'header').elements.length, 1); // unchanged
    c.dispose();
  });

  test('multi-source clipboard + band selected keeps per-source-band paste',
      () {
    final JetReportDesignerController c = _open()
      ..select('h1')
      ..addToSelection('d1');
    c.copy();
    c.selectBand('detail'); // a band IS selected, but clipboard spans 2 bands
    c.paste();

    // Each copy returns to its own source band, not the selected one.
    expect(_band(c, 'header').elements.length, 2); // h1 + its copy
    expect(_band(c, 'detail').elements.length, 3); // d1, d2 + d1's copy
    c.dispose();
  });
}
