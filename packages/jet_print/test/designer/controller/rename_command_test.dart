// Rename-element and rename-band command unit tests (spec 017 / Task 4).
//
// Low-level: drives DesignerDocument + command classes directly, no controller.
// Mirrors the fixture construction pattern from band_walker_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';
import 'package:jet_print/src/designer/controller/commands/rename_band_command.dart';
import 'package:jet_print/src/designer/controller/commands/rename_element_command.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';
import 'package:jet_print/src/designer/controller/selection.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

const JetRect _r = JetRect(x: 0, y: 0, width: 10, height: 10);

/// Smallest definition: one detail band with one text element.
DesignerDocument _docWith(TextElement el) => DesignerDocument(
      definition: ReportDefinition(
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
                elements: <ReportElement>[el],
              )),
            ],
          ),
        ),
      ),
      selection: Selection.empty,
    );

/// Finds the element with [id] in the detail band.
ReportElement? _findElement(DesignerDocument doc, String id) {
  for (final Band b in allBands(doc.definition)) {
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
  group('RenameElementCommand', () {
    test('sets the element name', () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi'),
      );
      final DesignerDocument after =
          const RenameElementCommand(id: 't1', name: 'Greeting').apply(doc);
      expect(_findElement(after, 't1')?.name, 'Greeting');
    });

    test('clears the name with null', () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi', name: 'Old'),
      );
      final DesignerDocument after =
          const RenameElementCommand(id: 't1', name: null).apply(doc);
      expect(_findElement(after, 't1')?.name, isNull);
    });

    test('is a no-op (value-equal) when name is already set to the same value',
        () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi', name: 'Same'),
      );
      final DesignerDocument after =
          const RenameElementCommand(id: 't1', name: 'Same').apply(doc);
      expect(after.definition, doc.definition);
    });

    test('leaves other elements untouched', () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi'),
      );
      final DesignerDocument after =
          const RenameElementCommand(id: 'no-such', name: 'X').apply(doc);
      expect(after.definition, doc.definition);
    });
  });

  group('RenameBandCommand', () {
    test('sets the band name', () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi'),
      );
      final DesignerDocument after =
          const RenameBandCommand(bandId: 'detail', name: 'Lines').apply(doc);
      final Band? band = findBand(after.definition, 'detail');
      expect(band?.name, 'Lines');
    });

    test('clears the band name with null', () {
      final DesignerDocument doc = DesignerDocument(
        definition: ReportDefinition(
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
                  name: 'Old name',
                  elements: const <ReportElement>[],
                )),
              ],
            ),
          ),
        ),
        selection: Selection.empty,
      );
      final DesignerDocument after =
          const RenameBandCommand(bandId: 'detail', name: null).apply(doc);
      final Band? band = findBand(after.definition, 'detail');
      expect(band?.name, isNull);
    });

    test('is a no-op (value-equal) when name is already the same value', () {
      final DesignerDocument doc = DesignerDocument(
        definition: ReportDefinition(
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
                  name: 'Same',
                  elements: const <ReportElement>[],
                )),
              ],
            ),
          ),
        ),
        selection: Selection.empty,
      );
      final DesignerDocument after =
          const RenameBandCommand(bandId: 'detail', name: 'Same').apply(doc);
      expect(after.definition, doc.definition);
    });

    test('preserves elements inside the renamed band', () {
      final DesignerDocument doc = _docWith(
        const TextElement(id: 't1', bounds: _r, text: 'hi'),
      );
      final DesignerDocument after =
          const RenameBandCommand(bandId: 'detail', name: 'Lines').apply(doc);
      final Band? band = findBand(after.definition, 'detail');
      expect(band?.elements.length, 1);
      expect(band?.elements.first.id, 't1');
    });
  });
}
