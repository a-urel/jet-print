// Crosstab authoring commands (spec B), exercised black-box through the public
// controller API — never by constructing a command and calling apply().
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// The crosstab with id [id], reached by walking the public tree — this suite
/// is a black-box consumer, so it never imports the designer's internal
/// walker.
Crosstab? _find(ReportDefinition def, String id) => def.body.root.children
    .whereType<CrosstabNode>()
    .map((CrosstabNode n) => n.crosstab)
    .where((Crosstab c) => c.id == id)
    .firstOrNull;

/// The seeding inputs a caller resolves from the schema: two scalars and one
/// numeric, so the rule has a distinct field for each of its three slots.
const List<FieldDef> _fields = <FieldDef>[
  FieldDef('region', type: JetFieldType.string),
  FieldDef('quarter', type: JetFieldType.string),
  FieldDef('amount', type: JetFieldType.double),
];

ReportDefinition _emptyDef() => const ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 12)),
          ],
        ),
      ),
    );

JetReportDesignerController _controller() =>
    JetReportDesignerController(definition: _emptyDef());

String _create(JetReportDesignerController c) {
  c.createCrosstab(c.definition.body.root.id, fields: _fields);
  return c.selection.crosstabId!;
}

List<Diagnostic> _errors(ReportDefinition def) => validate(def)
    .where((Diagnostic d) => d.severity == DiagnosticSeverity.error)
    .toList();

void main() {
  test('a created crosstab is born valid, bound and selected', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    final List<Diagnostic> errors = _errors(c.definition);
    expect(errors, isEmpty,
        reason: errors.map((Diagnostic d) => d.message).join('; '));
    final Crosstab ct = _find(c.definition, id)!;
    expect(ct.rowGroups.single.expression, r'$F{region}');
    expect(ct.columnGroups.single.expression, r'$F{quarter}');
    expect(ct.measures.single.expression, r'$F{amount}');
    expect(ct.measures.single.aggregate, JetCalculation.sum);
    expect(ct.collectionField, isNull);
    expect(c.selection.crosstabId, id);
  });

  test('with no numeric field the measure counts instead of summing', () {
    final JetReportDesignerController c = _controller();
    c.createCrosstab(c.definition.body.root.id, fields: const <FieldDef>[
      FieldDef('region', type: JetFieldType.string)
    ]);
    final Crosstab ct = _find(c.definition, c.selection.crosstabId!)!;
    expect(ct.measures.single.aggregate, JetCalculation.count);
    expect(_errors(c.definition), isEmpty);
  });

  test('creation is refused when nothing can be bucketed by', () {
    final JetReportDesignerController c = _controller();
    final ReportDefinition before = c.definition;
    c.createCrosstab(c.definition.body.root.id, fields: const <FieldDef>[]);
    c.createCrosstab('nope', fields: _fields);
    expect(c.definition, before);
    expect(c.selection.crosstabId, isNull);
  });

  test('rename, bind and delete each undo in exactly one step', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    final ReportDefinition afterCreate = c.definition;

    c.renameCrosstab(id, 'Pivot');
    expect(_find(c.definition, id)!.name, 'Pivot');
    c.undo();
    expect(c.definition, afterCreate);

    c.setCrosstabCollection(id, 'lines');
    expect(_find(c.definition, id)!.collectionField, 'lines');
    c.setCrosstabCollection(id, null);
    expect(_find(c.definition, id)!.collectionField, isNull,
        reason: 'a null collection must clear, not be ignored by copyWith');
    c.undo();
    c.undo();
    expect(c.definition, afterCreate);

    c.deleteCrosstab(id);
    expect(_find(c.definition, id), isNull);
    expect(c.selection.isEmpty, isTrue);
    c.undo();
    expect(c.definition, afterCreate);
  });

  test('style and visibility round-trip through the controller', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    c.setCrosstabStyle(
        id, _find(c.definition, id)!.style.copyWith(rowHeight: 22));
    expect(_find(c.definition, id)!.style.rowHeight, 22);
    c.setCrosstabVisible(id, const BoolProperty(value: false));
    expect(_find(c.definition, id)!.visible.value, isFalse);
  });

  test('the last row group, column group and measure cannot be removed', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    final Crosstab ct = _find(c.definition, id)!;
    final ReportDefinition before = c.definition;
    c.removeCrosstabGroup(id, ct.rowGroups.single.id);
    c.removeCrosstabGroup(id, ct.columnGroups.single.id);
    c.removeCrosstabMeasure(id, ct.measures.single.id);
    expect(c.definition, before,
        reason: 'a refusal must neither edit the model nor add history');
    expect(_errors(c.definition), isEmpty);
  });

  test('a second measure can be added, edited, moved and removed', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    c.addCrosstabMeasure(id, fieldName: 'units');
    expect(_find(c.definition, id)!.measures, hasLength(2));
    final String m2 = _find(c.definition, id)!.measures.last.id;
    expect(_find(c.definition, id)!.measures.last.expression, r'$F{units}');

    c.updateCrosstabMeasure(id, m2,
        (CrosstabMeasure m) => m.copyWith(aggregate: JetCalculation.average));
    expect(_find(c.definition, id)!.measures.last.aggregate,
        JetCalculation.average);

    c.moveCrosstabMeasure(id, m2, -1);
    expect(_find(c.definition, id)!.measures.first.id, m2);

    c.removeCrosstabMeasure(id, m2);
    expect(_find(c.definition, id)!.measures, hasLength(1));
    expect(_errors(c.definition), isEmpty);
  });

  test('a second axis level can be added, edited, moved and removed', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    c.addCrosstabGroup(id, row: true, fieldName: 'city');
    expect(_find(c.definition, id)!.rowGroups, hasLength(2));
    expect(_find(c.definition, id)!.columnGroups, hasLength(1),
        reason: 'row: true must not touch the column axis');
    final String g2 = _find(c.definition, id)!.rowGroups.last.id;

    c.updateCrosstabGroup(
        id, g2, (CrosstabGroup g) => g.copyWith(sort: CrosstabSort.descending));
    expect(
        _find(c.definition, id)!.rowGroups.last.sort, CrosstabSort.descending);

    c.moveCrosstabGroup(id, g2, -1);
    expect(_find(c.definition, id)!.rowGroups.first.id, g2);

    c.removeCrosstabGroup(id, g2);
    expect(_find(c.definition, id)!.rowGroups, hasLength(1));

    c.addCrosstabGroup(id, row: false, fieldName: 'year');
    expect(_find(c.definition, id)!.columnGroups, hasLength(2));
    expect(_find(c.definition, id)!.rowGroups, hasLength(1));
    expect(_errors(c.definition), isEmpty);
  });

  test('a blank field name adds nothing', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    final ReportDefinition before = c.definition;
    c.addCrosstabGroup(id, row: true, fieldName: '  ');
    c.addCrosstabMeasure(id, fieldName: '');
    expect(c.definition, before);
  });

  test('moving a crosstab reorders it among its siblings', () {
    final JetReportDesignerController c = _controller();
    final String id = _create(c);
    expect(c.definition.body.root.children.last, isA<CrosstabNode>());
    c.moveCrosstab(id, -1);
    expect(c.definition.body.root.children.first, isA<CrosstabNode>(),
        reason: 'above the first band a crosstab prints before the row loop');
    final ReportDefinition atTop = c.definition;
    c.moveCrosstab(id, -1);
    expect(c.definition, atTop, reason: 'a clamped move records no history');
  });

  // One end-to-end authoring walk: every step the Outline and Properties
  // surfaces drive, then undo all the way back. Pins that each step is exactly
  // one history entry and that the definition returns to the original value.
  test('create, edit, add, reorder, delete — then undo back to the start', () {
    final JetReportDesignerController c = _controller();
    final ReportDefinition original = c.definition;

    final String id = _create(c);
    c.renameCrosstab(id, 'Sales pivot');
    c.updateCrosstabGroup(id, _find(c.definition, id)!.rowGroups.single.id,
        (CrosstabGroup g) => g.copyWith(sort: CrosstabSort.descending));
    c.addCrosstabMeasure(id, fieldName: 'units');
    c.moveCrosstab(id, -1);
    c.deleteCrosstab(id);
    expect(_find(c.definition, id), isNull);

    for (int i = 0; i < 6; i++) {
      c.undo();
    }
    expect(c.definition, original);
    expect(_errors(c.definition), isEmpty);
  });
}
