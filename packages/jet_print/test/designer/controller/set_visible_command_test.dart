// Tests for SetElementVisibleCommand / SetBandVisibleCommand via the public
// controller API. Controller construction and undo patterns are copied from
// binding_command_test.dart and band_selection_resize_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/domain/bool_property.dart';

/// The detail band's single element of type [T].
T _only<T extends ReportElement>(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements
        .whereType<T>()
        .single;

/// The band with the given [id] from the body tree.
Band _band(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .firstWhere((BandNode n) => n.band.id == id)
        .band;

void main() {
  test('setElementVisible sets visible and is undoable', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;

    // Default visible is BoolProperty() — value: true, no expression.
    expect(_only<TextElement>(c).visible, const BoolProperty());

    c.setElementVisible(id, const BoolProperty(value: false));
    expect(_only<TextElement>(c).visible, const BoolProperty(value: false));

    c.undo();
    expect(_only<TextElement>(c).visible, const BoolProperty());
  });

  test('setBandVisible sets visible and is undoable', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.setBandVisible('detail', BoolProperty(expression: r'$F{x}'));
    expect(_band(c, 'detail').visible.expression, r'$F{x}');

    c.undo();
    expect(_band(c, 'detail').visible, const BoolProperty());
  });

  test('setElementVisible on equal value is a no-op (no history entry)', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;

    // Make one real change, then repeat the same value — identical call must
    // not add a second history entry. A single undo should revert to default.
    c.setElementVisible(id, const BoolProperty(value: false));
    c.setElementVisible(id, const BoolProperty(value: false)); // no-op
    c.undo(); // reverts the one real change
    expect(_only<TextElement>(c).visible, const BoolProperty());
    // createElement is still on the stack, but no second setElementVisible entry.
    c.undo(); // reverts createElement
    expect(c.canUndo, isFalse);
  });
}
