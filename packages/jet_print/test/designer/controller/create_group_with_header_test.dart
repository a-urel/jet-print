// Controller unit test: createGroupWithHeader adds a group AND its header band as
// one undo step, selecting the header band, and leaves the definition valid.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('createGroupWithHeader adds a group with a header band, selecting it', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.createGroupWithHeader(c.definition.body.root.id);

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    final GroupLevel g = groups.single;
    expect(g.header, isNotNull, reason: 'the group has a header band');
    expect(g.header!.type, BandType.groupHeader);
    expect(c.selection.bandId, g.header!.id, reason: 'the header band is selected');
  });

  test('createGroupWithHeader leaves a valid definition (parseable placeholder key, no errors)', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createGroupWithHeader(c.definition.body.root.id);
    final bool anyErrors = c.diagnostics
        .any((Diagnostic d) => d.severity == DiagnosticSeverity.error);
    expect(anyErrors, isFalse, reason: 'the placeholder key parses; ids/names are unique');
  });

  test('createGroupWithHeader is one undo step', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupWithHeader(c.definition.body.root.id);
    c.undo();
    expect(c.definition, before);
  });
}
