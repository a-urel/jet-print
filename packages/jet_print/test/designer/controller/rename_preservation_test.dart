// Regression tests: display `name` survives every command that rebuilds an
// element/band via a direct constructor instead of `copyWith` (spec-031 class
// silent-drop bug, fixed in this branch).
//
// Each test: rename first, then mutate — asserts the name is still present.
// Black-box: drives only the public controller surface.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const JetRect _r = JetRect(x: 0, y: 0, width: 10, height: 10);

/// A definition with a text element `t1`, an image element `img1`, and the
/// detail band `detail` — all named up-front so tests can check preservation.
ReportDefinition _defWithNames() => ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 100,
              name: 'MyBand',
              elements: <ReportElement>[
                TextElement(
                  id: 't1',
                  bounds: _r,
                  text: 'hello',
                  name: 'MyText',
                ),
                ImageElement(
                  id: 'img1',
                  bounds: _r,
                  source: const FieldImageSource('photo'),
                  name: 'MyImage',
                ),
              ],
            )),
          ],
        ),
      ),
    );

ReportElement? _elem(ReportDefinition def, String id) {
  for (final Band b in allBands(def)) {
    for (final ReportElement e in b.elements) {
      if (e.id == id) return e;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('name preserved after setValue', () {
    test('literal text edit keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      // t1 already has name 'MyText' from the fixture.
      c.setValue('t1', 'new text');
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });

    test('binding via setValue keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setValue('t1', '[fieldName]');
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });
  });

  group('name preserved after setFormat', () {
    test('setting a format keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setFormat('t1', '#,##0.00');
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });

    test('clearing the format (empty string) keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setFormat('t1', ''); // clears format
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });
  });

  group('name preserved after setBinding / clearBinding', () {
    test('setBinding keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setBinding('t1', r'$F{customerName}');
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });

    test('clearBinding keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setBinding('t1', r'$F{customerName}');
      c.clearBinding('t1');
      expect(_elem(c.definition, 't1')?.name, 'MyText');
    });
  });

  group('name preserved after setImageField', () {
    test('binding an image to a field keeps element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      c.setImageField('img1', 'avatarField');
      expect(_elem(c.definition, 'img1')?.name, 'MyImage');
    });
  });

  group('name preserved after removeColumnLayout', () {
    test('removing column layout keeps band name', () {
      // Need a pure single-detail body to allow setColumnLayout.
      final ReportDefinition base = ReportDefinition(
        name: 'labels',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 80,
                name: 'MyBand',
                elements: const <ReportElement>[
                  TextElement(
                    id: 't',
                    bounds: JetRect(x: 0, y: 0, width: 100, height: 20),
                    text: 'x',
                  ),
                ],
              )),
            ],
          ),
        ),
      );

      final JetReportDesignerController c =
          JetReportDesignerController(definition: base);
      addTearDown(c.dispose);

      c.setColumnLayout(
        'detail',
        const ColumnLayout(
            columnCount: 2, columnWidth: 200, columnSpacing: 8, rowSpacing: 4),
      );
      c.removeColumnLayout('detail');

      expect(findBand(c.definition, 'detail')?.name, 'MyBand');
      expect(findBand(c.definition, 'detail')?.columnLayout, isNull);
    });
  });

  group('paste preserves element name', () {
    test('pasted copy inherits the source element name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWithNames());
      addTearDown(c.dispose);
      // Select the named text element and paste.
      c.select('t1');
      c.copy();
      c.paste();
      // The pasted copy will have a fresh id; find element that is NOT 't1'
      // in the detail band.
      final Band detail =
          (c.definition.body.root.children.single as BandNode).band;
      final ReportElement pasted = detail.elements
          .firstWhere((ReportElement e) => e.id != 't1' && e is TextElement);
      expect(pasted.name, 'MyText',
          reason: 'paste via JSON round-trip should preserve name');
    });
  });
}
