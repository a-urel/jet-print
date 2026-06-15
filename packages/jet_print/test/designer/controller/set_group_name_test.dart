import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  ReportDefinition grouped() {
    final JetReportDesignerController c = JetReportDesignerController();
    c.createGroupWithHeader(c.definition.body.root.id);
    final ReportDefinition d = c.definition;
    c.dispose();
    return d;
  }

  test('setGroupName renames the group as one undoable step', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: grouped());
    addTearDown(c.dispose);
    final String groupId = c.definition.body.root.groups.single.id;

    c.setGroupName(groupId, 'invoice');

    expect(c.definition.body.root.groups.single.name, 'invoice');
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.definition.body.root.groups.single.name, groupId);
  });

  test('setGroupName is a no-op for an unknown group', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: grouped());
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.setGroupName('nope', 'x');
    expect(c.definition, before);
  });
}
