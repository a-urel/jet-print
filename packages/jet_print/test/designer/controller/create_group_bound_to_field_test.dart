// Controller unit test: createGroupBoundToField adds a group keyed to a scalar
// field ($F{field}), named after it, plus a selected header band — one undo step.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('adds a group keyed to the field, named after it, header selected', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    final GroupLevel g = groups.single;
    expect(g.name, 'invoiceNo');
    expect(g.key, r'$F{invoiceNo}');
    expect(g.header, isNotNull, reason: 'the group has a header band');
    expect(g.header!.type, BandType.groupHeader);
    expect(c.selection.bandId, g.header!.id,
        reason: 'the header band is selected');
  });

  test('is one undo step', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');
    c.undo();
    expect(c.definition, before);
  });

  test('no-op for an unknown scope', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField('nope', 'invoiceNo');
    expect(c.definition, before);
  });

  test('no-op for a blank field name', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField(c.definition.body.root.id, '');
    expect(c.definition, before);
  });

  test('leaves a valid definition (the \$F{field} key parses, no errors)', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');
    final bool anyErrors = c.diagnostics
        .any((Diagnostic d) => d.severity == DiagnosticSeverity.error);
    expect(anyErrors, isFalse,
        reason: 'a field-bound group is born without diagnostic errors');
  });
}
