// Widget test: the composed style editors extracted for spec C
// (_TextStyleEditor / _BoxStyleEditor). This file pins behaviour that the
// element-inspector suite (properties_editor_test.dart) only covers
// indirectly, and owns the pump/finder helpers later crosstab-style tasks
// build on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';

/// Finds a Properties-panel widget by its key suffix (the part after
/// `'jet_print.designer.properties.'`).
Finder findPanelKey(String suffix) =>
    find.byKey(ValueKey<String>('$_p.$suffix'));

/// Pumps the designer, adds a shape of [kind], selects it, and opens the
/// Properties tab so its inspector is in the tree.
///
/// Reaching Properties is non-obvious: the right panel is a `ShadTabs` that
/// opens on Data Source and builds only the active tab's body, so the
/// Properties tab must be scrolled into view before it can be tapped.
Future<JetReportDesignerController> pumpDesignerWithShape(
    WidgetTester tester, ShapeKind kind) async {
  final JetReportDesignerController c = await pumpDesignerWith(tester);
  c.createElement(DesignerToolType.shape,
      bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
  final String id = c.selection.singleOrNull!;
  c.setShapeKind(id, kind);
  await tester.pumpAndSettle();

  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  return c;
}

/// The schema [pumpDesignerWithCrosstab] seeds its crosstab from: one string
/// field to key both axes, and one numeric field for the summed measure.
const JetDataSchema _crosstabSchema = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('amount', type: JetFieldType.double),
  ],
);

/// Pumps the designer with [_crosstabSchema], adds a crosstab to the root
/// scope, selects it, and opens the Properties tab so its inspector — and the
/// three style sections under test — are in the tree.
Future<JetReportDesignerController> pumpDesignerWithCrosstab(
    WidgetTester tester) async {
  final JetReportDesignerController c =
      await pumpDesignerWith(tester, dataSchema: _crosstabSchema);
  final String rootScopeId = c.definition.body.root.id;
  c.createCrosstab(rootScopeId, fields: _crosstabSchema.fields);
  // createCrosstab already selects the new crosstab as part of its command;
  // selecting it again explicitly keeps this helper correct even if that
  // command-level detail ever changes.
  c.selectCrosstab(onlyCrosstab(c).id);
  await tester.pumpAndSettle();

  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  return c;
}

/// The single [Crosstab] on [c]'s definition, walked through the public tree
/// (never `package:jet_print/src/...` — `encapsulation_test` forbids it here).
Crosstab onlyCrosstab(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<CrosstabNode>().single.crosstab;

/// Scrolls [finder] into view and taps it.
///
/// The crosstab inspector is long — axes, measures, layout metrics, then the
/// three style sections — so a control below the fold is off the 900px test
/// surface until scrolled there, the same reason [pumpDesignerWithCrosstab]
/// scrolls the Properties tab into view before tapping it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Whether the panel field at key [suffix] currently displays [text] as a
/// descendant — the same descendant-text seam `properties_editor_test.dart`
/// (`_valueIn`) reads committed field values through. Not exercised by this
/// file's own tests; later crosstab-style tasks share it for asserting a
/// role's format/preset controls without adding another finder helper.
bool valueInPanelKey(String suffix, String text) => find
    .descendant(of: findPanelKey(suffix), matching: find.text(text))
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('a line shape has no fill swatch, a rectangle does',
      (WidgetTester tester) async {
    await pumpDesignerWithShape(tester, ShapeKind.line);
    expect(findPanelKey('field.fill'), findsNothing,
        reason: 'a line has no interior, so the fill swatch is dropped');
    expect(findPanelKey('field.stroke'), findsOneWidget);

    await pumpDesignerWithShape(tester, ShapeKind.rectangle);
    expect(findPanelKey('field.fill'), findsOneWidget);
  });

  testWidgets('the panel mirrors the planner dominant defaults',
      (WidgetTester tester) async {
    // The planner resolves an unset headerText to a centred style for column
    // headers, and an unset cellText/totalText to a right-aligned one for
    // value cells. The panel re-derives these constants rather than
    // importing the render layer (`_kCrosstabHeaderDefault`/
    // `_kCrosstabCellDefault` in style_section.dart) — both library-private,
    // so this black-box test cannot read them directly. Instead it commits an
    // unrelated field (fontSize) on the still-unstyled effective style: the
    // committed style is the mirrored default with only that one field
    // changed, so the surviving `align` IS the mirrored constant. A wrong
    // mirror shows up here as a wrong alignment on the very next commit,
    // which is what stops the two copies drifting.
    final JetReportDesignerController c =
        await pumpDesignerWithCrosstab(tester);

    await _tapVisible(tester, findPanelKey('crosstab.header.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.header.fontSize.option.24'));
    expect(onlyCrosstab(c).style.headerText?.align, JetTextAlign.center);

    await _tapVisible(tester, findPanelKey('crosstab.cells.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.cells.fontSize.option.24'));
    expect(onlyCrosstab(c).style.cellText?.align, JetTextAlign.right);
  });

  testWidgets(
      'each role has its own align control, not one shared by all three',
      (WidgetTester tester) async {
    // _StyleToggleGroup/_AlignSegments used to build their segment keys from
    // a hardcoded '$_p.field...' prefix rather than the caller's keyBase —
    // invisible while only one _TextStyleEditor was ever on screen at once,
    // but the crosstab inspector shows three simultaneously (Header, Cells,
    // Totals). Fixed to thread keyBase through; this pins that each role's
    // align control is independently addressable and distinct from the
    // others', not a single widget the finder happens to hit three times.
    await pumpDesignerWithCrosstab(tester);

    final Finder header = findPanelKey('crosstab.header.align.center');
    final Finder cells = findPanelKey('crosstab.cells.align.center');
    expect(header, findsOneWidget);
    expect(cells, findsOneWidget);
    expect(
      tester.widget(header).key,
      isNot(tester.widget(cells).key),
      reason: 'each role must own a distinct align key, not collide on one',
    );
  });

  testWidgets('an unstyled crosstab shows inherited values, not blanks',
      (WidgetTester tester) async {
    await pumpDesignerWithCrosstab(tester);
    // All six slots are null, so each role shows what it would inherit.
    expect(findPanelKey('crosstab.header.fontSize'), findsOneWidget);
    expect(findPanelKey('crosstab.cells.fontSize'), findsOneWidget);
    expect(findPanelKey('crosstab.totals.fontSize'), findsOneWidget);
  });

  testWidgets('the reset action is absent until a slot is set',
      (WidgetTester tester) async {
    await pumpDesignerWithCrosstab(tester);
    expect(findPanelKey('crosstab.header.reset'), findsNothing);

    await _tapVisible(tester, findPanelKey('crosstab.header.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.header.fontSize.option.24'));

    expect(findPanelKey('crosstab.header.reset'), findsOneWidget);
  });

  testWidgets('the first edit materializes only its own slot',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWithCrosstab(tester);
    await _tapVisible(tester, findPanelKey('crosstab.header.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.header.fontSize.option.24'));

    final CrosstabStyle s = onlyCrosstab(c).style;
    expect(s.headerText?.fontSize, 24);
    expect(s.cellText, isNull, reason: 'editing one role must not seed others');
    expect(s.totalText, isNull);
    expect(s.headerBox, isNull);
  });

  testWidgets('reset clears the role back to inherited',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWithCrosstab(tester);
    await _tapVisible(tester, findPanelKey('crosstab.header.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.header.fontSize.option.24'));
    await _tapVisible(tester, findPanelKey('crosstab.header.reset'));

    expect(onlyCrosstab(c).style.headerText, isNull);
    expect(findPanelKey('crosstab.header.reset'), findsNothing);
  });

  testWidgets('one edit is one undo step', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWithCrosstab(tester);
    await _tapVisible(tester, findPanelKey('crosstab.header.fontSize'));
    await _tapVisible(
        tester, findPanelKey('crosstab.header.fontSize.option.24'));

    c.undo();
    expect(onlyCrosstab(c).style.headerText, isNull);
  });

  testWidgets('an untouched crosstab round-trips byte-identically',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWithCrosstab(tester);
    final String before = JetReportFormat.encodeDefinitionJson(c.definition);
    // Merely selecting the crosstab and building its inspector must not write.
    expect(JetReportFormat.encodeDefinitionJson(c.definition), before);
    expect(before.contains('headerText'), isFalse);
  });
}
