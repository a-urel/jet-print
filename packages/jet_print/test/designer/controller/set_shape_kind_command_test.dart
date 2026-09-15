// Controller setShapeKind() unit tests.
//
// Black-box: drives only the public controller surface. setShapeKind() is the
// single undoable mutator behind the shape gallery. It must change the form
// while preserving bounds/style, be exactly one history step, no-op (no history,
// no notify) when the form is already active, reset the line-only flipDiagonal
// when leaving a line, and clear a preserved unknownForm on a deliberate pick.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../../support/report_builders.dart';

/// A one-band report holding a single [ShapeElement] [shape], so a form change
/// can be driven and asserted against a known element.
ReportDefinition _report(ShapeElement shape) =>
    oneBandReport(elements: <ReportElement>[shape]);

void main() {
  const JetRect bounds = JetRect(x: 12, y: 8, width: 60, height: 40);
  const JetBoxStyle style = JetBoxStyle(stroke: JetColor.black, strokeWidth: 2);

  group('setShapeKind — changes the form, preserves the box', () {
    test('a pick changes kind while preserving bounds and style', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.rectangle, style: style)),
      );
      c.setShapeKind('s', ShapeKind.hexagon);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.hexagon);
      expect(elementById<ShapeElement>(c, 's').bounds, bounds);
      expect(elementById<ShapeElement>(c, 's').style, style);
      c.dispose();
    });
  });

  group('setShapeKind — no-op on the already-active form', () {
    test('picking the current form records no history and notifies no one', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(
            const ShapeElement(id: 's', bounds: bounds, kind: ShapeKind.star)),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeKind('s', ShapeKind.star); // same form

      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.star);
      expect(c.canUndo, isFalse, reason: 'a no-op arms no undo');
      expect(notifications, 0, reason: 'a no-op fires no notification');
      c.dispose();
    });
  });

  group('setShapeKind — one notifying step (C4.x scaffolding)', () {
    test('a real pick is a single notifying, undoable step', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.rectangle)),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeKind('s', ShapeKind.triangle);

      expect(notifications, 1, reason: 'exactly one notification per pick');
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  group('setShapeKind — line/flip coherence', () {
    test('switching off a line resets the line-only flipDiagonal', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.line, flipDiagonal: true)),
      );
      c.setShapeKind('s', ShapeKind.diamond);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.diamond);
      expect(elementById<ShapeElement>(c, 's').flipDiagonal, isFalse,
          reason: 'flipDiagonal is meaningless off a line');
      c.dispose();
    });

    test('staying on / returning to a line keeps its diagonal coherent', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.rectangle)),
      );
      c.setShapeKind('s', ShapeKind.line);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.line);
      expect(elementById<ShapeElement>(c, 's').flipDiagonal,
          isFalse); // default diagonal
      c.dispose();
    });
  });

  group('setShapeKind — clears a preserved unknownForm', () {
    test('a deliberate pick clears unknownForm', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's',
            bounds: bounds,
            kind: ShapeKind.rectangle,
            unknownForm: 'octagon')),
      );
      c.setShapeKind('s', ShapeKind.star);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.star);
      expect(elementById<ShapeElement>(c, 's').unknownForm, isNull);
      c.dispose();
    });

    test('picking rectangle on an unknown-form shape clears it (not a no-op)',
        () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's',
            bounds: bounds,
            kind: ShapeKind.rectangle,
            unknownForm: 'octagon')),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      // The rendered kind is already rectangle, but unknownForm != null, so the
      // gallery shows nothing highlighted and picking rectangle IS a real edit.
      c.setShapeKind('s', ShapeKind.rectangle);

      expect(elementById<ShapeElement>(c, 's').unknownForm, isNull);
      expect(notifications, 1, reason: 'clearing an unknown form is a change');
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  // --- US2: undo / redo -------------------------------
  group('setShapeKind — undo / redo', () {
    test('one undo restores the prior form; one redo reapplies the new form',
        () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.hexagon)),
      );
      c.setShapeKind('s', ShapeKind.star);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.star);

      c.undo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.hexagon,
          reason: 'one-step undo');

      c.redo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.star,
          reason: 'one-step redo');
      c.dispose();
    });
  });

  group('setShapeKind — one step per pick, no orphans', () {
    test('rectangle→hexagon→star is exactly two undoable steps', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.rectangle)),
      );
      c.setShapeKind('s', ShapeKind.hexagon);
      c.setShapeKind('s', ShapeKind.star);

      expect(c.canUndo, isTrue);
      c.undo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.hexagon);
      c.undo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.rectangle);
      expect(c.canUndo, isFalse,
          reason: 'exactly two steps — no orphaned intermediate entry');

      // Redo replays both, in order.
      c.redo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.hexagon);
      c.redo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.star);
      c.dispose();
    });

    test('a no-op pick adds nothing to the undo stack', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const ShapeElement(
            id: 's', bounds: bounds, kind: ShapeKind.rectangle)),
      );
      c.setShapeKind('s', ShapeKind.diamond); // one real step
      c.setShapeKind('s', ShapeKind.diamond); // no-op — must not stack

      c.undo();
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.rectangle);
      expect(c.canUndo, isFalse, reason: 'the no-op pushed no history');
      c.dispose();
    });
  });
}
