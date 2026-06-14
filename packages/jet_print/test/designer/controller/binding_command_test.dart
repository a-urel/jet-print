// Binding commands (US2 / FR-009, FR-012, FR-013).
//
// Public-API controller tests (no `src/`): bind a text element to an
// expression, bind an image element to a field, clear a binding, and confirm
// undo/redo plus no-op-pushes-no-history. The element model carries the binding
// (TextElement.expression / FieldImageSource) — these methods set it as one
// undoable step.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// The detail band's single element of type [T] (the default definition's
/// `'detail'` band).
T _only<T extends ReportElement>(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements
        .whereType<T>()
        .single;

void main() {
  group('text binding', () {
    test('setBinding sets an expression; clearBinding reverts to static', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;

      expect(_only<TextElement>(c).expression, isNull);
      c.setBinding(id, r'$F{customerName}');
      expect(_only<TextElement>(c).expression, r'$F{customerName}');

      c.clearBinding(id);
      expect(_only<TextElement>(c).expression, isNull);
    });

    test('undo restores the prior binding state; redo re-applies it', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;

      c.setBinding(id, r'$F{total}');
      expect(_only<TextElement>(c).expression, r'$F{total}');
      c.undo();
      expect(_only<TextElement>(c).expression, isNull); // back to unbound
      c.redo();
      expect(_only<TextElement>(c).expression, r'$F{total}');
    });

    test('a no-op setBinding pushes no history entry', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;

      c.setBinding(id, r'$F{a}');
      c.setBinding(id, r'$F{a}'); // identical → no-op, no new history entry
      c.undo(); // single undo reverts the one real change
      expect(_only<TextElement>(c).expression, isNull);
    });
  });

  group('image binding', () {
    test('setImageField binds an image element to a field source', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.createElement(DesignerToolType.image,
          bandId: 'detail', at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;

      c.setImageField(id, 'logo');
      final ImageElement img = _only<ImageElement>(c);
      expect(img.source, isA<FieldImageSource>());
      expect((img.source as FieldImageSource).field, 'logo');
    });
  });

  group('createBoundElement', () {
    test('creates a bound text element at the drop point', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.createBoundElement(
        bandId: 'detail',
        at: const JetOffset(12, 12),
        expression: r'$F{customerName}',
      );
      final TextElement t = _only<TextElement>(c);
      expect(t.expression, r'$F{customerName}');
      expect(c.selection.singleOrNull, t.id); // new element is selected
    });
  });
}
