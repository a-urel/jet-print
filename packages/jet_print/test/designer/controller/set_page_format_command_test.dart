// Controller setPageFormat() unit tests (018 / Foundational / contracts §C3–C8).
//
// Black-box: drives only the public controller + serialization surface.
// setPageFormat() is the single undoable mutator behind the rebuilt PAGE
// section. It must clamp its input to a usable page (positive content area),
// commit as exactly one history entry, no-op on an unchanged page, leave element
// anchors untouched, and round-trip losslessly through the codec.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A small report with one element at a known band-relative anchor, so a page
/// change can be shown not to move content (C8.1).
ReportDefinition _report({PageFormat page = PageFormat.a4Portrait}) =>
    ReportDefinition(
      name: 'Page test',
      page: page,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 120,
              elements: <ReportElement>[
                TextElement(
                  id: 'e1',
                  bounds: JetRect(x: 12, y: 8, width: 100, height: 18),
                  text: 'x',
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The single element of the single detail band, for the anchor assertions.
TextElement _onlyText(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .single
        .band
        .elements
        .single as TextElement;

void main() {
  group('setPageFormat — orientation & resize (C3.1)', () {
    test('swapping width/height rotates A4 portrait to landscape', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      final PageFormat page = c.definition.page;
      c.setPageFormat(page.copyWith(width: page.height, height: page.width));
      expect(c.definition.page.width, closeTo(841.89, 1e-6));
      expect(c.definition.page.height, closeTo(595.28, 1e-6));
      expect(c.definition.page.margins, page.margins,
          reason: 'orientation swap leaves margins untouched');
      c.dispose();
    });
  });

  group('setPageFormat — clamp keeps a usable page (C4.1/C4.3/C3.4)', () {
    test('margins exceeding the width are scaled to leave positive content',
        () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(
          page: const PageFormat(
            width: 200,
            height: 400,
            margins: JetEdgeInsets.all(28.35),
          ),
        ),
      );
      // left+right (150+100=250) exceed the 200pt width.
      c.setPageFormat(c.definition.page.copyWith(
          margins:
              const JetEdgeInsets(left: 150, top: 10, right: 100, bottom: 10)));
      final PageFormat p = c.definition.page;
      expect(p.margins.left + p.margins.right, lessThan(p.width),
          reason: 'a positive horizontal content area must remain');
      expect(p.margins.left, greaterThan(0));
      expect(p.margins.right, greaterThan(0));
      c.dispose();
    });

    test('margins exactly consuming the page are corrected', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(
              page: const PageFormat(
                  width: 100, height: 100, margins: JetEdgeInsets.all(0))));
      c.setPageFormat(c.definition.page.copyWith(
          margins:
              const JetEdgeInsets(left: 50, top: 50, right: 50, bottom: 50)));
      final PageFormat p = c.definition.page;
      expect(p.margins.left + p.margins.right, lessThan(p.width));
      expect(p.margins.top + p.margins.bottom, lessThan(p.height));
      c.dispose();
    });

    test('a zero/negative custom dimension clamps to a positive minimum', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      c.setPageFormat(c.definition.page.copyWith(width: 0, height: -5));
      expect(c.definition.page.width, greaterThan(0));
      expect(c.definition.page.height, greaterThan(0));
      c.dispose();
    });

    test('a valid page is committed unchanged (clamp is idempotent, C4.2)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      const PageFormat valid = PageFormat(
        width: 612,
        height: 792,
        margins: JetEdgeInsets.all(14.17),
      );
      c.setPageFormat(valid);
      expect(c.definition.page, valid,
          reason: 'a valid page passes through the clamp unchanged');
      c.dispose();
    });
  });

  group('setPageFormat — undo/redo & no-op (C5)', () {
    test('a page change undoes in one step to the exact prior page (C5.1)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      final PageFormat before = c.definition.page;
      c.setPageFormat(const PageFormat(
          width: 612, height: 792, margins: JetEdgeInsets.all(28.35)));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.page, before);
      expect(c.canUndo, isFalse, reason: 'one page edit = one history entry');
      c.dispose();
    });

    test('redo re-applies the change (C5.2)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      const PageFormat letter = PageFormat(
          width: 612, height: 792, margins: JetEdgeInsets.all(28.35));
      c.setPageFormat(letter);
      c.undo();
      c.redo();
      expect(c.definition.page, letter);
      c.dispose();
    });

    test('setPageFormat with the current page is a no-op (C5.3)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      int notifications = 0;
      c.addListener(() => notifications++);
      c.setPageFormat(c.definition.page);
      expect(notifications, 0,
          reason: 'an identical page notifies no listener');
      expect(c.canUndo, isFalse, reason: 'no history entry for a no-op');
      c.dispose();
    });
  });

  group('setPageFormat — persistence & content (C6.1/C8.1)', () {
    test('an edited page round-trips losslessly through the codec (C6.1)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      // Letter, landscape, Narrow margins.
      c.setPageFormat(const PageFormat(
          width: 792, height: 612, margins: JetEdgeInsets.all(14.17)));
      final ReportDefinition restored = JetReportFormat.decodeDefinition(
          JetReportFormat.encodeDefinition(c.definition));
      expect(restored.page, c.definition.page);
      c.dispose();
    });

    test('changing to a smaller page preserves element anchors (C8.1)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _report());
      final JetRect before = _onlyText(c).bounds;
      c.setPageFormat(const PageFormat(
          width: 300, height: 400, margins: JetEdgeInsets.all(14.17)));
      final JetRect after = _onlyText(c).bounds;
      expect(after, before,
          reason: 'a page resize neither moves nor deletes content');
      c.dispose();
    });
  });
}
