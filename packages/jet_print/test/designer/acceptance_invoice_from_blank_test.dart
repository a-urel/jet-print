// Acceptance (SC headline): from a blank report, build a grouped master/detail
// invoice using only the new authoring affordances, and assert the tree shape +
// validity. Mirrors what a user does via the Outline "+", the Data Source "+",
// and the inspectors.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('a blank report can be built into a grouped master/detail invoice', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    final String root = c.definition.body.root.id;

    // 1) Group the records by invoice (Outline "Add group" → edit key in band).
    c.createGroupWithHeader(root);
    final String groupId = c.definition.body.root.groups.single.id;
    c.setGroupKey(groupId, r'$F{invoiceNo}');

    // 2) Add the line-items list (Data Source "+ as list" on `lines`).
    c.createListWithBand(root, collectionField: 'lines');
    final NestedScope list =
        c.definition.body.root.children.whereType<NestedScope>().single;
    final String lineBandId =
        list.scope.children.whereType<BandNode>().single.band.id;

    // 3) Drop a couple of bound fields into the line band (Data Source scalar drag).
    c.createBoundElement(
        bandId: lineBandId, at: const JetOffset(8, 8), expression: r'$F{description}');
    c.createBoundElement(
        bandId: lineBandId, at: const JetOffset(180, 8), expression: r'$F{lineTotal}');

    // Assert the shape (re-read from the current definition — the model is
    // immutable so `list` captured above is a stale snapshot).
    final DetailScope rootScope = c.definition.body.root;
    expect(rootScope.groups, hasLength(1));
    expect(rootScope.groups.single.key, r'$F{invoiceNo}');
    final NestedScope liveList =
        rootScope.children.whereType<NestedScope>().single;
    expect(liveList.scope.collectionField, 'lines');
    final Band line = liveList.scope.children.whereType<BandNode>().single.band;
    expect(line.elements.whereType<TextElement>(), hasLength(2));

    // Assert validity: no error diagnostics (everything is bound/parseable).
    expect(
        c.diagnostics.where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty);
  });
}
