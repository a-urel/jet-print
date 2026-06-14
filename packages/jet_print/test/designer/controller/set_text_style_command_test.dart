// Controller setTextStyle() unit tests (021 / US1 / contracts C5, C9).
//
// Black-box: drives only the public controller surface. setTextStyle() is the
// single undoable mutator behind every Font-section editor. It must replace
// the whole style as exactly one history step with one notification, and be a
// strict no-op (no history, no notify) when the target is missing, is not a
// TextElement, or already carries an equal style.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A one-band report holding [elements], so a style change can be driven and
/// asserted against known elements.
ReportDefinition _report(List<ReportElement> elements) => ReportDefinition(
      name: 'Text style test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 120,
                elements: elements)),
          ],
        ),
      ),
    );

TextElement _text(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id) as TextElement;

const JetRect _bounds = JetRect(x: 12, y: 8, width: 120, height: 24);

const TextElement _element = TextElement(
  id: 't',
  bounds: _bounds,
  text: 'Hello',
  style: JetTextStyle(fontSize: 14, weight: JetFontWeight.medium),
);

const JetTextStyle _next = JetTextStyle(
  fontFamily: 'Default',
  fontSize: 24,
  weight: JetFontWeight.bold,
  italic: true,
  underline: true,
  color: JetColor(0xFF1E40AF),
  align: JetTextAlign.center,
);

void main() {
  group('setTextStyle — replaces the style (C2/C5)', () {
    test('a commit replaces the whole style, preserving text and bounds', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      c.setTextStyle('t', _next);
      expect(_text(c, 't').style, _next);
      expect(_text(c, 't').text, 'Hello');
      expect(_text(c, 't').bounds, _bounds);
      c.dispose();
    });

    test('a real change is a single notifying, undoable step', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setTextStyle('t', _next);

      expect(notifications, 1, reason: 'exactly one notification per commit');
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  group('setTextStyle — no-ops (C5 / FR-013)', () {
    test('an equal style records no history and notifies no one', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setTextStyle(
          't', const JetTextStyle(fontSize: 14, weight: JetFontWeight.medium));

      expect(c.canUndo, isFalse, reason: 'a no-op arms no undo');
      expect(notifications, 0, reason: 'a no-op fires no notification');
      c.dispose();
    });

    test('a missing target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setTextStyle('nope', _next);

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });

    test('a non-text target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const <ReportElement>[
          _element,
          ShapeElement(id: 's', bounds: _bounds, kind: ShapeKind.rectangle),
        ]),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setTextStyle('s', _next);

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });
  });

  group('setTextStyle — undo / redo (C9)', () {
    test('one undo restores the prior style; one redo reapplies the new one',
        () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      c.setTextStyle('t', _next);
      expect(_text(c, 't').style, _next);

      c.undo();
      expect(_text(c, 't').style,
          const JetTextStyle(fontSize: 14, weight: JetFontWeight.medium),
          reason: 'one-step undo');

      c.redo();
      expect(_text(c, 't').style, _next, reason: 'one-step redo');
      c.dispose();
    });

    test('two commits are exactly two undoable steps', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      c.setTextStyle('t', _element.style.copyWith(fontSize: 36));
      c.setTextStyle('t', _next);

      c.undo();
      expect(_text(c, 't').style.fontSize, 36);
      c.undo();
      expect(_text(c, 't').style.fontSize, 14);
      expect(c.canUndo, isFalse, reason: 'exactly two steps');
      c.dispose();
    });
  });
}
