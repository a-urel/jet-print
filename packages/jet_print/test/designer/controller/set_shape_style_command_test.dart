// Controller setShapeStyle() unit tests.
//
// Black-box: drives only the public controller surface. setShapeStyle() is the
// single undoable mutator behind the Appearance editors. Same matrix as
// setTextStyle: whole-style replacement in exactly one history step with one
// notification; strict no-op (no history, no notify) for a missing target, a
// non-shape target, or an equal style.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../../support/report_builders.dart';

const JetRect _bounds = JetRect(x: 12, y: 8, width: 60, height: 40);

const ShapeElement _element = ShapeElement(
  id: 's',
  bounds: _bounds,
  kind: ShapeKind.rectangle,
  style: JetBoxStyle(stroke: JetColor.black, strokeWidth: 2),
);

const JetBoxStyle _next = JetBoxStyle(
  fill: JetColor(0x3300FF00),
  stroke: JetColor(0xFF112233),
  strokeWidth: 5,
);

void main() {
  group('setShapeStyle — replaces the style', () {
    test('a commit replaces the whole style, preserving kind and bounds', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      c.setShapeStyle('s', _next);
      expect(elementById<ShapeElement>(c, 's').style, _next);
      expect(elementById<ShapeElement>(c, 's').kind, ShapeKind.rectangle);
      expect(elementById<ShapeElement>(c, 's').bounds, _bounds);
      c.dispose();
    });

    test('an explicit-null fill/stroke (None) commits and round-trips', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      c.setShapeStyle('s', _element.style.copyWith(stroke: null));
      expect(elementById<ShapeElement>(c, 's').style.stroke, isNull);
      expect(elementById<ShapeElement>(c, 's').style.strokeWidth, 2,
          reason: 'width untouched');
      c.dispose();
    });

    test('a real change is a single notifying, undoable step', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeStyle('s', _next);

      expect(notifications, 1);
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  group('setShapeStyle — no-ops', () {
    test('an equal style records no history and notifies no one', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeStyle(
          's', const JetBoxStyle(stroke: JetColor.black, strokeWidth: 2));

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });

    test('a missing target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeStyle('nope', _next);

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });

    test('a non-shape target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: oneBandReport(elements: const <ReportElement>[
          _element,
          TextElement(id: 't', bounds: _bounds, text: 'Hi'),
        ]),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setShapeStyle('t', _next);

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });
  });

  group('setShapeStyle — undo / redo', () {
    test('one undo restores the prior style; one redo reapplies', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      c.setShapeStyle('s', _next);

      c.undo();
      expect(elementById<ShapeElement>(c, 's').style,
          const JetBoxStyle(stroke: JetColor.black, strokeWidth: 2));

      c.redo();
      expect(elementById<ShapeElement>(c, 's').style, _next);
      c.dispose();
    });

    test('width-0 then width-back keeps the remembered stroke color', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: oneBandReport(elements: const <ReportElement>[_element]));
      // Width to 0 — the color must stay on the style.
      c.setShapeStyle('s',
          elementById<ShapeElement>(c, 's').style.copyWith(strokeWidth: 0));
      expect(elementById<ShapeElement>(c, 's').style.stroke, JetColor.black);
      expect(elementById<ShapeElement>(c, 's').style.strokeWidth, 0);
      // Width back above 0 — the outline returns in its remembered color.
      c.setShapeStyle('s',
          elementById<ShapeElement>(c, 's').style.copyWith(strokeWidth: 3));
      expect(elementById<ShapeElement>(c, 's').style.stroke, JetColor.black);
      expect(elementById<ShapeElement>(c, 's').style.strokeWidth, 3);
      c.dispose();
    });
  });
}
