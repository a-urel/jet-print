// Properties panel editor test (model-driven, T072).
//
// The Properties tab is a context-aware inspector bound to the controller:
//  * a single selected element → editable X/Y/W/H (setGeometry) and, for a text
//    element, its text (setText); every edit is one undoable step;
//  * a selected band → editable height (setBandHeight);
//  * the selected report → read-only page info;
//  * nothing / a multi-selection → a friendly empty state.
// The fields reflect the live model (a canvas move updates them).
//
// Drives the public `JetReportDesigner` only (Properties reached via its tab).
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/test_fonts.dart';
import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _emptyHint = find.byKey(const ValueKey<String>('$_p.empty'));
Finder _field(String name) => find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));
Finder _valueIn(String name, String text) =>
    find.descendant(of: _field(name), matching: find.text(text));

/// Whether the field [name]'s trigger paints a swatch in [expected] — the
/// compact color box reflects the current color by fill, not by hex text.
bool _hasSwatch(WidgetTester tester, String name, Color expected) => tester
    .widgetList<Container>(
        find.descendant(of: _field(name), matching: find.byType(Container)))
    .any((Container c) =>
        c.decoration is BoxDecoration &&
        (c.decoration! as BoxDecoration).color == expected);

// --- PAGE section (018) seams ---
Finder _preview = find.byKey(const ValueKey<String>('$_p.pagePreview'));
Finder _paperOption(String name) =>
    find.byKey(ValueKey<String>('$_p.field.paper.option.$name'));
Finder _marginOption(String kind) =>
    find.byKey(ValueKey<String>('$_p.field.marginPreset.option.$kind'));

// --- Shape gallery (020) seams ---
/// The gallery thumbnail for a shape form, by its [ShapeKind.name].
Finder _shapeThumb(String name) =>
    find.byKey(ValueKey<String>('$_p.shape.$name'));

/// The seven forms the gallery offers, in roster order (C1.4). `line` is a valid
/// ShapeKind but is intentionally NOT offered — a diagonal is not a useful
/// authoring primitive (a rule is a thin rectangle).
const List<String> _shapeForms = <String>[
  'rectangle',
  'ellipse',
  'triangle',
  'diamond',
  'pentagon',
  'hexagon',
  'star',
];

/// The left margin-guide inset in the preview (guide left minus sheet left), the
/// testable expression of the live left margin's proportion.
double _previewLeftInset(WidgetTester tester) {
  final Rect sheet = tester
      .getRect(find.byKey(const ValueKey<String>('$_p.pagePreview.sheet')));
  final Rect guide = tester
      .getRect(find.byKey(const ValueKey<String>('$_p.pagePreview.guide')));
  return guide.left - sheet.left;
}

/// The aspect ratio (width / height) the preview is currently drawing the sheet
/// at — the testable expression of the page's size and orientation.
double _previewAspect(WidgetTester tester) {
  final Rect sheet = tester
      .getRect(find.byKey(const ValueKey<String>('$_p.pagePreview.sheet')));
  return sheet.width / sheet.height;
}

/// A report whose page is exactly [w] × [h] points (default margins), so the
/// PAGE controls can be driven against a known size. A single detail band lives
/// in the master scope (the reified equivalent of the old flat detail band).
ReportDefinition _pageDefinition(double w, double h) => ReportDefinition(
      name: 'Page',
      page: PageFormat(
          width: w, height: h, margins: const JetEdgeInsets.all(28.35)),
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 100)),
          ],
        ),
      ),
    );

/// Every element in the definition, walking the furniture, the once-bands, and
/// the master-scope tree (the reified replacement for `template.bands.expand`).
List<ReportElement> _allElements(JetReportDesignerController c) {
  final ReportDefinition def = c.definition;
  final List<ReportElement> out = <ReportElement>[];
  void addBand(Band? b) {
    if (b != null) out.addAll(b.elements);
  }

  void addScope(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      addBand(g.header);
      addBand(g.footer);
    }
    for (final ScopeNode node in s.children) {
      switch (node) {
        case BandNode(band: final Band band):
          addBand(band);
        case NestedScope(scope: final DetailScope inner):
          addScope(inner);
      }
    }
  }

  addBand(def.furniture.pageHeader);
  addBand(def.furniture.pageFooter);
  addBand(def.furniture.columnHeader);
  addBand(def.furniture.columnFooter);
  addBand(def.furniture.background);
  addBand(def.body.title);
  addBand(def.body.summary);
  addBand(def.body.noData);
  addScope(def.body.root);
  return out;
}

ReportElement _elementById(JetReportDesignerController c, String id) =>
    _allElements(c).firstWhere((ReportElement e) => e.id == id);

/// Every band in the definition, in tree order (furniture, once-bands, the
/// master scope's groups' header/footer bands, and per-row bands).
List<Band> _allBands(JetReportDesignerController c) {
  final ReportDefinition def = c.definition;
  final List<Band> out = <Band>[];
  void add(Band? b) {
    if (b != null) out.add(b);
  }

  void addScope(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      add(g.header);
      add(g.footer);
    }
    for (final ScopeNode node in s.children) {
      switch (node) {
        case BandNode(band: final Band band):
          add(band);
        case NestedScope(scope: final DetailScope inner):
          addScope(inner);
      }
    }
  }

  add(def.furniture.pageHeader);
  add(def.furniture.pageFooter);
  add(def.furniture.columnHeader);
  add(def.furniture.columnFooter);
  add(def.furniture.background);
  add(def.body.title);
  add(def.body.summary);
  add(def.body.noData);
  addScope(def.body.root);
  return out;
}

Band _bandById(JetReportDesignerController c, String id) =>
    _allBands(c).firstWhere((Band b) => b.id == id);

/// The group with [id] anywhere in the scope tree.
GroupLevel _groupById(JetReportDesignerController c, String id) {
  GroupLevel? found;
  void visit(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      if (g.id == id) found = g;
    }
    for (final ScopeNode node in s.children) {
      if (node is NestedScope) visit(node.scope);
    }
  }

  visit(c.definition.body.root);
  return found!;
}

JetRect _bounds(JetReportDesignerController c, String id) =>
    _elementById(c, id).bounds;

String _text(JetReportDesignerController c, String id) =>
    (_elementById(c, id) as TextElement).text;

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<String> _addText(WidgetTester tester, JetReportDesignerController c,
    {JetOffset at = const JetOffset(20, 30)}) async {
  c.createElement(DesignerToolType.text, bandId: firstDetailBandId(c), at: at);
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  return id;
}

/// Adds a default (rectangle) shape, selects it, and returns its id (020).
Future<String> _addShape(WidgetTester tester, JetReportDesignerController c,
    {JetOffset at = const JetOffset(20, 30)}) async {
  c.createElement(DesignerToolType.shape, bandId: firstDetailBandId(c), at: at);
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  return id;
}

ShapeElement _shapeOf(JetReportDesignerController c, String id) =>
    _elementById(c, id) as ShapeElement;

JetTextStyle _textStyleOf(JetReportDesignerController c, String id) =>
    (_elementById(c, id) as TextElement).style;

/// The controller's history revision — unchanged across an interaction ⇔ that
/// interaction recorded no undo entry (no-op commits must not pollute history).
int _undoDepth(JetReportDesignerController c) => c.revision;

/// A one-band report holding a single text element `t` styled with [style], so
/// the Font editors can be asserted against known values (021 / C2). The detail
/// band lives in the master scope (the reified equivalent of a flat band).
JetReportDesignerController _styledTextController(JetTextStyle style) =>
    JetReportDesignerController(
      definition: ReportDefinition(
        name: 'Styled',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 120,
                elements: <ReportElement>[
                  TextElement(
                    id: 't',
                    bounds: const JetRect(x: 10, y: 10, width: 160, height: 24),
                    text: 'Hello',
                    style: style,
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );

/// Pumps the designer over [_styledTextController]'s definition with `t`
/// selected and the Properties tab open.
Future<JetReportDesignerController> _pumpStyledText(
    WidgetTester tester, JetTextStyle style) async {
  final JetReportDesignerController c = _styledTextController(style);
  await pumpDesignerWith(tester, controller: c);
  await _openProperties(tester);
  c.select('t');
  await tester.pumpAndSettle();
  return c;
}

/// Like [_pumpStyledText] but builds the designer with host [fonts] (022 / US1),
/// so the family picker enumerates them. The external controller is disposed on
/// tear-down (the designer never disposes a host-owned controller).
Future<JetReportDesignerController> _pumpStyledTextWithFonts(
  WidgetTester tester,
  JetTextStyle style,
  List<JetFontFamily> fonts, {
  bool showBuiltInFonts = true,
}) async {
  final JetReportDesignerController c = _styledTextController(style);
  addTearDown(c.dispose);
  await pumpDesigner(
    tester,
    designer: JetReportDesigner(
      controller: c,
      fonts: fonts,
      showBuiltInFonts: showBuiltInFonts,
    ),
  );
  await _openProperties(tester);
  c.select('t');
  await tester.pumpAndSettle();
  return c;
}

/// A one-family host font list ("Acme Brand", regular only) built from the
/// shared test-fixture font bytes.
List<JetFontFamily> _brandFonts() => <JetFontFamily>[
      JetFontFamily(
        name: 'Acme Brand',
        faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
      ),
    ];

/// The semantics of the Font-section control at key suffix [name].
SemanticsNode _semanticsOf(WidgetTester tester, String name) =>
    tester.getSemantics(_field(name));

void main() {
  group('properties — empty state', () {
    testWidgets('shows a hint and no geometry fields when nothing is selected',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      await _openProperties(tester);

      expect(_emptyHint, findsOneWidget);
      expect(_field('x'), findsNothing);
    });
  });

  group('properties — element', () {
    testWidgets('reflects the selected element geometry',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addText(tester, c); // bounds (20, 30, 144, 18)

      expect(_valueIn('x', '20'), findsOneWidget);
      expect(_valueIn('y', '30'), findsOneWidget);
      expect(_valueIn('width', '144'), findsOneWidget);
      expect(_valueIn('height', '18'), findsOneWidget);
    });

    testWidgets('editing X commits to the model as one undoable step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      await tester.enterText(_editable('x'), '60');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_bounds(c, id).x, 60);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(_bounds(c, id).x, 20);
    });

    testWidgets('the width stepper bumps the size by one',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      final double before = _bounds(c, id).width;

      await tester.tap(find.descendant(
          of: _field('width'), matching: find.byIcon(LucideIcons.chevronUp)));
      await tester.pumpAndSettle();

      expect(_bounds(c, id).width, greaterThan(before));
    });

    testWidgets('a text element exposes a single editable value field',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      expect(_field('value'), findsOneWidget);
      // The two-field Text + Binding pair is gone (013 / FR-001, SC-001).
      expect(_field('text'), findsNothing);
      expect(_field('binding'), findsNothing);
      await tester.enterText(_editable('value'), 'Hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_text(c, id), 'Hello');
    });

    testWidgets('a non-text element has no value field',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.createElement(DesignerToolType.shape,
          bandId: firstDetailBandId(c), at: const JetOffset(10, 10));
      await tester.pumpAndSettle();

      expect(_field('x'), findsOneWidget); // geometry still shown
      expect(_field('value'), findsNothing);
    });

    testWidgets('the fields reflect a model change made elsewhere',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      expect(_valueIn('x', '20'), findsOneWidget);

      c.setGeometry(id, x: 88); // e.g. a canvas drag / nudge
      await tester.pumpAndSettle();
      expect(_valueIn('x', '88'), findsOneWidget);
    });
  });

  group('properties — band & report', () {
    testWidgets('a selected band exposes an editable height',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectBand('detail'); // detail, height 200
      await tester.pumpAndSettle();

      expect(_valueIn('bandHeight', '200'), findsOneWidget);
      await tester.enterText(_editable('bandHeight'), '260');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_bandById(c, 'detail').height, 260);
    });

    testWidgets('the group header band exposes a Start-on-new-page toggle',
        (WidgetTester tester) async {
      // The page-break flag is a GROUP property (spec 024) written through the
      // one GroupLevel, but it is edited from the band the author sees — the
      // group's header band (2026-06-14 design note), not an abstract node.
      final JetReportDesignerController c = JetReportDesignerController(
        definition: const ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'g1',
                  name: 'invoice',
                  key: r'$F{invoiceNo}',
                  header:
                      Band(id: 'gh', type: BandType.groupHeader, height: 30),
                ),
              ],
              children: <ScopeNode>[
                BandNode(Band(id: 'detail', type: BandType.detail, height: 40)),
              ],
            ),
          ),
        ),
      );
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectBand('gh'); // the group's header band carries the group section
      await tester.pumpAndSettle();

      final Finder toggle = _field('groupNewPage');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        _groupById(c, 'g1').startNewPage,
        isTrue,
      );
    });

    testWidgets('a non-group band shows no group toggle',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectBand('detail'); // detail band in the default definition
      await tester.pumpAndSettle();
      expect(_field('groupNewPage'), findsNothing);
    });

    testWidgets('the selected report shows read-only info, no geometry fields',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      expect(_field('x'), findsNothing);
      expect(
        find.descendant(
            of: find.byKey(kRightPanelKey), matching: find.text('Report')),
        findsOneWidget,
      );
    });
  });

  group('properties — report name', () {
    testWidgets('the report exposes its name as an editable primary field',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _pageDefinition(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      // The Name field is present and reflects the live definition name.
      expect(_field('reportName'), findsOneWidget);
      expect(_valueIn('reportName', 'Page'), findsOneWidget);
    });

    testWidgets('editing the Name renames the report (one undoable step)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _pageDefinition(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.enterText(_editable('reportName'), 'Invoice');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.definition.name, 'Invoice');

      // Exactly one history entry: undo restores the prior name.
      c.undo();
      expect(c.definition.name, 'Page');
    });

    testWidgets('a blank Name reverts, keeping the report named',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _pageDefinition(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.enterText(_editable('reportName'), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.definition.name, 'Page', reason: 'blank entry is not committed');
    });
  });

  group('properties — page (US1 paper type)', () {
    testWidgets(
        'PAGE names the paper type and shows the preview, no selection '
        '(C1.1/C9.1/C9.4)', (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      // The default A4 page is named (with its size), not raw points (C1.1).
      expect(
          find.descendant(
              of: _field('paper'), matching: find.textContaining('A4')),
          findsOneWidget);
      // The Office-style page-sample preview is present (C9.1) ...
      expect(_preview, findsOneWidget);
      // ... rendered at the page's aspect ratio (A4 portrait → taller, < 1).
      expect(_previewAspect(tester), lessThan(1));
      // The PAGE controls are present/editable with nothing selected (C9.4).
      expect(_field('paper'), findsOneWidget);
    });

    testWidgets('selecting Letter resizes the page, margins unchanged (C1.2)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      final JetEdgeInsets marginsBefore = c.definition.page.margins;

      await tester.tap(_field('paper'));
      await tester.pumpAndSettle();
      // Each option names its size, e.g. "A4 (210 × 297 mm)".
      expect(
          find.descendant(
              of: _paperOption('A4'), matching: find.text('A4 (210 × 297 mm)')),
          findsOneWidget);
      await tester.tap(_paperOption('Letter'));
      await tester.pumpAndSettle();

      expect(c.definition.page.width, 612);
      expect(c.definition.page.height, 792);
      expect(c.definition.page.margins, marginsBefore,
          reason: 'changing paper type leaves margins untouched');
      // The picker now reflects the new size by name.
      expect(
          find.descendant(
              of: _field('paper'), matching: find.textContaining('Letter')),
          findsOneWidget);
    });

    testWidgets('a page matching no preset reads Custom (C1.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _pageDefinition(500, 700));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      expect(
          find.descendant(of: _field('paper'), matching: find.text('Custom')),
          findsOneWidget);
      // Dimensions are unaltered by recognition.
      expect(c.definition.page.width, 500);
      expect(c.definition.page.height, 700);
    });
  });

  group('properties — page (US2 margins)', () {
    testWidgets('choosing Narrow sets all four sides and updates fields (C2.1)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.tap(_field('marginPreset'));
      await tester.pumpAndSettle();
      await tester.tap(_marginOption('narrow'));
      await tester.pumpAndSettle();

      expect(c.definition.page.margins, const JetEdgeInsets.all(14.17));
      expect(_valueIn('marginLeft', '14.2'), findsOneWidget);
      expect(_valueIn('marginBottom', '14.2'), findsOneWidget);
    });

    testWidgets('editing Left changes only Left and flips to Custom (C2.2)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.enterText(_editable('marginLeft'), '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.definition.page.margins.left, 50);
      expect(c.definition.page.margins.top, 28.35);
      expect(c.definition.page.margins.right, 28.35);
      expect(c.definition.page.margins.bottom, 28.35);
      expect(
          find.descendant(
              of: _field('marginPreset'), matching: find.text('Custom')),
          findsOneWidget);
    });

    testWidgets('a non-numeric margin entry reverts on blur (C2.4)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      final double before = c.definition.page.margins.left;

      await tester.enterText(_editable('marginLeft'), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.definition.page.margins.left, before,
          reason: 'invalid is rejected');
      expect(find.text('abc'), findsNothing);
      expect(_valueIn('marginLeft', '28.4'), findsOneWidget,
          reason: 'the field reverts to the last valid value');
    });

    testWidgets(
        'changing a margin moves the preview guide proportionally (C9.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      final double insetBefore = _previewLeftInset(tester);

      await tester.enterText(_editable('marginLeft'), '120');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_previewLeftInset(tester), greaterThan(insetBefore));
    });
  });

  group('properties — page (US3 orientation & custom)', () {
    testWidgets(
        'toggling Landscape swaps W/H and flips the preview (C3.1/C9.2)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      expect(_previewAspect(tester), lessThan(1)); // A4 portrait
      final double w = c.definition.page.width;
      final double h = c.definition.page.height;

      await tester.tap(find
          .byKey(const ValueKey<String>('$_p.field.orientation.landscape')));
      await tester.pumpAndSettle();

      expect(c.definition.page.width, h);
      expect(c.definition.page.height, w);
      expect(_previewAspect(tester), greaterThan(1)); // now landscape
    });

    testWidgets('editing a custom dimension reflects in the preview aspect',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _pageDefinition(300, 600));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      expect(_previewAspect(tester), closeTo(0.5, 0.001)); // 300 / 600

      await tester.tap(_field('pageWidth'));
      await tester.pumpAndSettle();
      await tester.enterText(_editable('pageWidth'), '900');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.definition.page.width, 900);
      expect(_previewAspect(tester), closeTo(1.5, 0.001)); // 900 / 600
    });

    testWidgets('a standard paper hides the custom W/H fields (C3.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      expect(_field('pageWidth'), findsNothing);
      expect(_field('pageHeight'), findsNothing);
    });

    testWidgets('Custom paper reveals W/H and adopts exact dims (C3.2/C3.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      expect(_field('pageWidth'), findsNothing); // hidden for A4 (C3.3)

      await tester.tap(_field('paper'));
      await tester.pumpAndSettle();
      await tester.tap(_paperOption('Custom'));
      await tester.pumpAndSettle();
      expect(_field('pageWidth'), findsOneWidget); // revealed (C3.2)

      await tester.enterText(_editable('pageWidth'), '300');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(_editable('pageHeight'), '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.definition.page.width, 300);
      expect(c.definition.page.height, 500);
    });

    testWidgets('a custom dimension field reverts invalid input (C3.5)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _pageDefinition(300, 500));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      expect(_field('pageWidth'), findsOneWidget); // 300×500 is custom

      await tester.enterText(_editable('pageWidth'), 'xyz');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.definition.page.width, 300, reason: 'invalid input is rejected');
    });
  });

  // --- Font-size picker (was the C4 number field) ---------------------------
  //
  // Font size moved to a preset dropdown — there is no free entry left to clamp.
  // The _NumberField clamp/reject primitive is still exercised by outline width
  // [0, 20] (shape-appearance group) and page width (invalid-input rejection).
  group('properties — font-size picker', () {
    testWidgets('picking a preset commits that size in one undo step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      final int undoDepthBefore = _undoDepth(c);

      await tester.tap(_field('fontSize'));
      await tester.pumpAndSettle();
      await tester.tap(_field('fontSize.option.24'));
      await tester.pumpAndSettle();

      expect(_textStyleOf(c, id).fontSize, 24);
      expect(_undoDepth(c), undoDepthBefore + 1, reason: 'one undoable step');
      expect(_valueIn('fontSize', '24'), findsOneWidget,
          reason: 'the trigger reflects the picked size');
    });

    testWidgets('a stored size outside the preset set still displays',
        (WidgetTester tester) async {
      // 22 is not a preset, so it shows on the trigger (un-check-marked),
      // mirroring the family picker's handling of an unavailable family.
      await _pumpStyledText(tester, const JetTextStyle(fontSize: 22));
      expect(_valueIn('fontSize', '22'), findsOneWidget);
    });
  });

  // --- Font section (021 / US1) --------------------------------------------
  group('properties — font section gating (C1)', () {
    testWidgets('a text element shows the full Font section',
        (WidgetTester tester) async {
      await _pumpStyledText(tester, JetTextStyle.fallback);

      expect(_field('fontFamily'), findsOneWidget);
      expect(_field('fontSize'), findsOneWidget);
      expect(_field('bold'), findsOneWidget);
      expect(_field('italic'), findsOneWidget);
      expect(_field('underline'), findsOneWidget);
      expect(_field('textColor'), findsOneWidget);
      expect(_field('align.left'), findsOneWidget);
      expect(_field('align.center'), findsOneWidget);
      expect(_field('align.right'), findsOneWidget);
    });

    testWidgets('no Font section for a shape element',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addShape(tester, c);

      expect(_field('fontFamily'), findsNothing);
      expect(_field('fontSize'), findsNothing);
      expect(_field('bold'), findsNothing);
      expect(_field('textColor'), findsNothing);
    });

    testWidgets('no Font section for a band, the report, or no selection',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      expect(_field('fontSize'), findsNothing); // nothing selected

      c.selectBand('detail');
      await tester.pumpAndSettle();
      expect(_field('fontSize'), findsNothing);

      c.selectReport();
      await tester.pumpAndSettle();
      expect(_field('fontSize'), findsNothing);
    });
  });

  group('properties — font binding (C2)', () {
    testWidgets('the editors display a styled element\'s effective values',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await _pumpStyledText(
        tester,
        const JetTextStyle(
          fontSize: 24,
          weight: JetFontWeight.bold,
          italic: true,
          underline: true,
          color: JetColor(0xFF1E40AF),
          align: JetTextAlign.center,
        ),
      );

      expect(_valueIn('fontSize', '24'), findsOneWidget);
      expect(_semanticsOf(tester, 'bold'), isSemantics(isSelected: true));
      expect(_semanticsOf(tester, 'italic'), isSemantics(isSelected: true));
      expect(_semanticsOf(tester, 'underline'), isSemantics(isSelected: true));
      expect(_hasSwatch(tester, 'textColor', const Color(0xFF1E40AF)), isTrue);
      expect(
          _semanticsOf(tester, 'align.center'), isSemantics(isSelected: true));
      expect(
          _semanticsOf(tester, 'align.left'), isSemantics(isSelected: false));
      sem.dispose();
    });

    testWidgets('a pre-feature fallback element displays the defaults',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await _pumpStyledText(tester, JetTextStyle.fallback);

      expect(_valueIn('fontSize', '12'), findsOneWidget);
      expect(_semanticsOf(tester, 'bold'), isSemantics(isSelected: false));
      expect(_semanticsOf(tester, 'italic'), isSemantics(isSelected: false));
      expect(_semanticsOf(tester, 'underline'), isSemantics(isSelected: false));
      expect(_hasSwatch(tester, 'textColor', const Color(0xFF000000)), isTrue);
      expect(_semanticsOf(tester, 'align.left'), isSemantics(isSelected: true));
      sem.dispose();
    });
  });

  group('properties — family picker (C3)', () {
    testWidgets(
        'lists the registry families, previewed in their own typeface, '
        'and a pick is one undoable commit', (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(fontFamily: 'Unknown Family'));

      await tester.tap(_field('fontFamily'));
      await tester.pumpAndSettle();

      // The default registry holds exactly the bundled default family.
      final Finder option = _field('fontFamily.option.Default');
      expect(option, findsOneWidget);
      final Text label = tester.widget<Text>(
          find.descendant(of: option, matching: find.byType(Text)));
      expect(label.style?.fontFamily, 'Default',
          reason: 'each item previews in its own typeface');

      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(_textStyleOf(c, 't').fontFamily, isNull,
          reason: 'picking the default family selects the renderer default');
      c.undo();
      expect(_textStyleOf(c, 't').fontFamily, 'Unknown Family',
          reason: 'one-step undo restores the stored family');
    });

    testWidgets(
        'an unregistered stored family appears marked unavailable and is '
        'preserved on unrelated edits', (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(fontFamily: 'Unknown Family'));

      // The trigger shows the unavailable marker without opening the menu.
      expect(find.textContaining('Unknown Family'), findsOneWidget);
      expect(find.textContaining('(unavailable)'), findsOneWidget);

      // An unrelated edit preserves the stored family verbatim.
      await tester.tap(_field('bold'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontFamily, 'Unknown Family');
      expect(_textStyleOf(c, 't').weight, JetFontWeight.bold);
    });

    testWidgets(
        'an unregistered family survives a save (never silently swapped) '
        '(C11 / US2)', (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(fontFamily: 'Unknown Family'));

      // An unrelated edit, then the host's save path (encode the live model).
      await tester.tap(_field('bold'));
      await tester.pumpAndSettle();
      final String json = JetReportFormat.encodeDefinitionJson(c.definition);
      expect(json, contains('Unknown Family'),
          reason: 'the stored family name is preserved on save (SC-003)');
      // And decoding brings it back unchanged.
      final ReportDefinition decoded =
          JetReportFormat.decodeDefinitionJson(json);
      final TextElement text = decoded.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .whereType<TextElement>()
          .single;
      expect(text.style.fontFamily, 'Unknown Family');
    });
  });

  group('properties — host family in the picker (C10 / US1)', () {
    testWidgets(
        'lists the host family after the built-ins, previewed in its own '
        'typeface, and applying it is one undoable commit',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledTextWithFonts(
          tester, const JetTextStyle(), _brandFonts());

      await tester.tap(_field('fontFamily'));
      await tester.pumpAndSettle();

      final Finder acme = _field('fontFamily.option.Acme Brand');
      expect(acme, findsOneWidget);
      // Built-ins precede the host family (the families order; C5).
      expect(
          tester.getTopLeft(acme).dy,
          greaterThan(
              tester.getTopLeft(_field('fontFamily.option.Default')).dy),
          reason: 'the host family is listed after the built-ins');
      // Previewed in its own typeface.
      final Text label = tester
          .widget<Text>(find.descendant(of: acme, matching: find.byType(Text)));
      expect(label.style?.fontFamily, 'Acme Brand',
          reason: 'the option previews in its own typeface');

      await tester.tap(acme);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontFamily, 'Acme Brand',
          reason: 'applying commits the host family name');
      c.undo();
      expect(_textStyleOf(c, 't').fontFamily, isNull,
          reason: 'one-step undo restores the prior (default) family');
    });

    testWidgets(
        'showBuiltInFonts: false hides the built-in Default but keeps the '
        'host family (022)', (WidgetTester tester) async {
      await _pumpStyledTextWithFonts(
          tester, const JetTextStyle(), _brandFonts(),
          showBuiltInFonts: false);

      // The trigger shows the neutral localized "Default" for the null-family
      // element rather than a built-in family name.
      expect(
          find.descendant(
              of: _field('fontFamily'), matching: find.text('Default')),
          findsOneWidget);

      await tester.tap(_field('fontFamily'));
      await tester.pumpAndSettle();

      expect(_field('fontFamily.option.Acme Brand'), findsOneWidget,
          reason: 'the host catalog family is still offered');
      expect(_field('fontFamily.option.Default'), findsNothing);
    });

    testWidgets('built-ins are shown by default (backward-compatible)',
        (WidgetTester tester) async {
      await _pumpStyledTextWithFonts(
          tester, const JetTextStyle(), _brandFonts());
      await tester.tap(_field('fontFamily'));
      await tester.pumpAndSettle();
      expect(_field('fontFamily.option.Default'), findsOneWidget);
      expect(_field('fontFamily.option.Acme Brand'), findsOneWidget);
    });

    testWidgets('a long family list scrolls so late options stay reachable',
        (WidgetTester tester) async {
      // 30 host families → the menu overflows the viewport; it must scroll, not
      // clip (022 — large catalogs).
      final List<JetFontFamily> many = <JetFontFamily>[
        for (int i = 0; i < 30; i++)
          JetFontFamily(
            name: 'Family ${i.toString().padLeft(2, '0')}',
            faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
          ),
      ];
      final JetReportDesignerController c =
          await _pumpStyledTextWithFonts(tester, const JetTextStyle(), many);

      await tester.tap(_field('fontFamily'));
      await tester.pumpAndSettle();

      // The last family is built (in the tree) but off-screen; reaching it
      // requires a working scroll view.
      final Finder last = _field('fontFamily.option.Family 29');
      expect(last, findsOneWidget);
      await tester.ensureVisible(last); // throws if nothing can scroll it
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontFamily, 'Family 29',
          reason: 'a late, scrolled-to option is selectable');
    });
  });

  group('properties — B/I/U toggles (C5)', () {
    testWidgets('Bold is active iff the weight is bold',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      for (final (JetFontWeight weight, bool active) in <(JetFontWeight, bool)>[
        (JetFontWeight.normal, false),
        (JetFontWeight.medium, false),
        (JetFontWeight.semiBold, false),
        (JetFontWeight.bold, true),
      ]) {
        final JetReportDesignerController c =
            _styledTextController(JetTextStyle(weight: weight));
        await pumpDesignerWith(tester, controller: c);
        await _openProperties(tester);
        c.select('t');
        await tester.pumpAndSettle();
        expect(_semanticsOf(tester, 'bold'), isSemantics(isSelected: active),
            reason: '${weight.name}: bold active ⟺ weight == bold');
      }
      sem.dispose();
    });

    testWidgets('a medium weight is preserved until the toggle is operated',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(weight: JetFontWeight.medium));

      // Unrelated edit: italic — the intermediate weight must survive.
      await tester.tap(_field('italic'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').weight, JetFontWeight.medium);
      expect(_textStyleOf(c, 't').italic, isTrue);

      // Press while inactive ⇒ bold; press while active ⇒ normal.
      await tester.tap(_field('bold'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').weight, JetFontWeight.bold);
      await tester.tap(_field('bold'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').weight, JetFontWeight.normal);
    });

    testWidgets('italic and underline map 1:1, each press one undo step',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await _pumpStyledText(tester, JetTextStyle.fallback);

      await tester.tap(_field('underline'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').underline, isTrue);

      await tester.tap(_field('italic'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').italic, isTrue);

      c.undo();
      expect(_textStyleOf(c, 't').italic, isFalse,
          reason: 'one undo reverts only the italic press');
      expect(_textStyleOf(c, 't').underline, isTrue);
      c.undo();
      expect(_textStyleOf(c, 't').underline, isFalse);
    });
  });

  group('properties — text color editor (C6)', () {
    testWidgets('the hex input shows #RRGGBB for opaque, #AARRGGBB translucent',
        (WidgetTester tester) async {
      await _pumpStyledText(
          tester, const JetTextStyle(color: JetColor(0x80FF8800)));
      // The compact trigger paints the colour; the formatted hex lives in the
      // popover's hex input.
      expect(_hasSwatch(tester, 'textColor', const Color(0x80FF8800)), isTrue);
      await tester.tap(_field('textColor'));
      await tester.pumpAndSettle();
      expect(_valueIn('textColor.hex', '#80FF8800'), findsOneWidget);
    });

    testWidgets('a swatch pick preserves the stored alpha, one undo step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(color: JetColor(0x80FF8800)));

      await tester.tap(_field('textColor'));
      await tester.pumpAndSettle();
      await tester.tap(_field('textColor.swatch.red'));
      await tester.pumpAndSettle();

      expect(_textStyleOf(c, 't').color, const JetColor(0x80EF4444),
          reason: 'swatch replaces RGB, stored alpha 0x80 is preserved');
      c.undo();
      expect(_textStyleOf(c, 't').color, const JetColor(0x80FF8800));
    });

    testWidgets('a 6-digit hex preserves alpha; an 8-digit hex sets it',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(color: JetColor(0x80FF8800)));

      await tester.tap(_field('textColor'));
      await tester.pumpAndSettle();
      await tester.enterText(_editable('textColor.hex'), '#1E40AF');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').color, const JetColor(0x801E40AF));

      await tester.tap(_field('textColor'));
      await tester.pumpAndSettle();
      await tester.enterText(_editable('textColor.hex'), '#33112233');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').color, const JetColor(0x33112233));
    });

    testWidgets('malformed hex is rejected, restored, and records no history',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(color: JetColor(0xFF1E40AF)));

      for (final String bad in <String>['#12', 'red', '#GGGGGG']) {
        final int before = _undoDepth(c);
        await tester.tap(_field('textColor'));
        await tester.pumpAndSettle();
        await tester.enterText(_editable('textColor.hex'), bad);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(_textStyleOf(c, 't').color, const JetColor(0xFF1E40AF),
            reason: '"$bad" must not commit');
        expect(_undoDepth(c), before, reason: '"$bad" records no history');
      }
      // The trigger still paints the last valid value.
      expect(_hasSwatch(tester, 'textColor', const Color(0xFF1E40AF)), isTrue);
    });

    testWidgets('the text color editor offers no None entry',
        (WidgetTester tester) async {
      await _pumpStyledText(tester, JetTextStyle.fallback);
      await tester.tap(_field('textColor'));
      await tester.pumpAndSettle();
      expect(_field('textColor.none'), findsNothing);
    });
  });

  group('properties — alignment segments (C2/C9)', () {
    testWidgets('clicking center then right re-aligns, one undo step each',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await _pumpStyledText(tester, JetTextStyle.fallback);

      await tester.tap(_field('align.center'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').align, JetTextAlign.center);

      await tester.tap(_field('align.right'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').align, JetTextAlign.right);

      c.undo();
      expect(_textStyleOf(c, 't').align, JetTextAlign.center);
      c.undo();
      expect(_textStyleOf(c, 't').align, JetTextAlign.left);
    });

    testWidgets('clicking the active segment records no history',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await _pumpStyledText(tester, JetTextStyle.fallback);
      final int before = _undoDepth(c);

      await tester.tap(_field('align.left')); // already active
      await tester.pumpAndSettle();

      expect(_undoDepth(c), before);
      expect(_textStyleOf(c, 't').align, JetTextAlign.left);
    });

    testWidgets(
        'a stored justify shows no active segment and survives unrelated '
        'edits', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final JetReportDesignerController c = await _pumpStyledText(
          tester, const JetTextStyle(align: JetTextAlign.justify));

      for (final String seg in <String>['left', 'center', 'right']) {
        expect(
            _semanticsOf(tester, 'align.$seg'), isSemantics(isSelected: false),
            reason: 'justify activates no segment');
      }

      await tester.tap(_field('bold')); // unrelated edit
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').align, JetTextAlign.justify,
          reason: 'justify is preserved verbatim until an alignment is picked');

      await tester.tap(_field('align.center'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').align, JetTextAlign.center);
      sem.dispose();
    });
  });

  group('properties — font undo & selection switching (C9)', () {
    testWidgets('the keyed font editors re-bind when selection switches',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await _pumpStyledText(tester, JetTextStyle.fallback);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(10, 60));
      final String other = c.selection.singleOrNull!;
      c.select('t');
      await tester.pumpAndSettle();

      // Give 't' a distinct size, then switch selection and come back: the
      // KeyedSubtree rebuilds the editors against whichever element is current.
      await tester.tap(_field('fontSize'));
      await tester.pumpAndSettle();
      await tester.tap(_field('fontSize.option.24'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontSize, 24);

      c.select(other);
      await tester.pumpAndSettle();
      expect(_valueIn('fontSize', '12'), findsOneWidget,
          reason: 'the other element binds its own default size');

      c.select('t');
      await tester.pumpAndSettle();
      expect(_valueIn('fontSize', '24'), findsOneWidget,
          reason: 'the editor re-binds to the stored value');
    });

    testWidgets('undo restores both the model and the displayed values',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await _pumpStyledText(tester, JetTextStyle.fallback);

      await tester.tap(_field('fontSize'));
      await tester.pumpAndSettle();
      await tester.tap(_field('fontSize.option.24'));
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontSize, 24);

      c.undo();
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, 't').fontSize, 12);
      expect(_valueIn('fontSize', '12'), findsOneWidget,
          reason: 'the editor tracks the restored value');
    });
  });

  // Font-label l10n for de/tr lives in localization_de_test.dart /
  // localization_tr_test.dart — one non-English locale per isolate (the CLDR
  // locale-switch leak documented in localization_test.dart).

  // --- Appearance section (021 / US2) ---------------------------------------
  group('properties — appearance gating (C1)', () {
    testWidgets('a closed shape shows fill, outline, and width controls',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addShape(tester, c); // a rectangle

      expect(_field('fill'), findsOneWidget);
      expect(_field('stroke'), findsOneWidget);
      expect(_field('strokeWidth'), findsOneWidget);
    });

    testWidgets('a line shape offers outline controls only — no fill control',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      c.setShapeKind(id, ShapeKind.line);
      await tester.pumpAndSettle();

      expect(_field('fill'), findsNothing);
      expect(_field('stroke'), findsOneWidget);
      expect(_field('strokeWidth'), findsOneWidget);
    });

    testWidgets('no Appearance section for a text element',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addText(tester, c);

      expect(_field('fill'), findsNothing);
      expect(_field('stroke'), findsNothing);
      expect(_field('strokeWidth'), findsNothing);
    });
  });

  group('properties — shape fill & outline none states (C7)', () {
    testWidgets('None commits fill: null and the editor shows the none state',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      c.setShapeStyle(
          id, _shapeOf(c, id).style.copyWith(fill: const JetColor(0xFF22C55E)));
      await tester.pumpAndSettle();

      await tester.tap(_field('fill'));
      await tester.pumpAndSettle();
      await tester.tap(_field('fill.none'));
      await tester.pumpAndSettle();

      expect(_shapeOf(c, id).style.fill, isNull);
      expect(
          find.descendant(
              of: _field('fill'), matching: find.byIcon(LucideIcons.ban)),
          findsOneWidget,
          reason: 'the compact swatch shows the none state (a ban glyph)');
      c.undo();
      expect(_shapeOf(c, id).style.fill, const JetColor(0xFF22C55E),
          reason: 'one-step undo restores the fill');
    });

    testWidgets('None commits stroke: null', (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);

      await tester.tap(_field('stroke'));
      await tester.pumpAndSettle();
      await tester.tap(_field('stroke.none'));
      await tester.pumpAndSettle();

      expect(_shapeOf(c, id).style.stroke, isNull);
      expect(
          find.descendant(
              of: _field('stroke'), matching: find.byIcon(LucideIcons.ban)),
          findsOneWidget);
    });

    testWidgets('the text color editor still has no None, the shape ones do',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addShape(tester, c);

      await tester.tap(_field('fill'));
      await tester.pumpAndSettle();
      expect(_field('fill.none'), findsOneWidget);
    });
  });

  group('properties — outline width picker (C7)', () {
    testWidgets('picking a preset commits that width in one undo step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      final int before = _undoDepth(c);

      await tester.tap(_field('strokeWidth'));
      await tester.pumpAndSettle();
      await tester.tap(_field('strokeWidth.option.0'));
      await tester.pumpAndSettle();

      expect(_shapeOf(c, id).style.strokeWidth, 0);
      expect(_undoDepth(c), before + 1, reason: 'one undoable step');
      expect(_valueIn('strokeWidth', '0'), findsOneWidget,
          reason: 'the trigger reflects the picked width');
    });

    testWidgets(
        'width 0 hides the outline but keeps the color; width > 0 restores it',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      c.setShapeStyle(id,
          _shapeOf(c, id).style.copyWith(stroke: const JetColor(0xFF1E40AF)));
      await tester.pumpAndSettle();

      await tester.tap(_field('strokeWidth'));
      await tester.pumpAndSettle();
      await tester.tap(_field('strokeWidth.option.0'));
      await tester.pumpAndSettle();
      expect(_shapeOf(c, id).style.strokeWidth, 0);
      expect(_shapeOf(c, id).style.stroke, const JetColor(0xFF1E40AF),
          reason: 'the stored color survives width 0 (no trapdoor)');

      await tester.tap(_field('strokeWidth'));
      await tester.pumpAndSettle();
      await tester.tap(_field('strokeWidth.option.0.5'));
      await tester.pumpAndSettle();
      expect(_shapeOf(c, id).style.strokeWidth, 0.5);
      expect(_shapeOf(c, id).style.stroke, const JetColor(0xFF1E40AF),
          reason: 'the outline returns in its remembered color');
    });
  });

  group('properties — shape editor undo & selection switch (C9)', () {
    testWidgets('a swatch pick on fill is one undoable step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      final JetColor? fillBefore = _shapeOf(c, id).style.fill;

      await tester.tap(_field('fill'));
      await tester.pumpAndSettle();
      await tester.tap(_field('fill.swatch.blue'));
      await tester.pumpAndSettle();

      expect(_shapeOf(c, id).style.fill, const JetColor(0xFF3B82F6));
      c.undo();
      expect(_shapeOf(c, id).style.fill, fillBefore);
    });

    testWidgets('switching selection re-binds the width picker to each shape',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      final String other =
          await _addShape(tester, c, at: const JetOffset(120, 30));
      c.select(id);
      await tester.pumpAndSettle();

      // Give `id` a distinct width, then switch away and back: the appearance
      // KeyedSubtree rebuilds the picker against whichever shape is current.
      await tester.tap(_field('strokeWidth'));
      await tester.pumpAndSettle();
      await tester.tap(_field('strokeWidth.option.0'));
      await tester.pumpAndSettle();
      expect(_shapeOf(c, id).style.strokeWidth, 0);

      c.select(other);
      await tester.pumpAndSettle();
      expect(_valueIn('strokeWidth', '1'), findsOneWidget,
          reason: 'the other shape binds its own default width');

      c.select(id);
      await tester.pumpAndSettle();
      expect(_valueIn('strokeWidth', '0'), findsOneWidget,
          reason: 're-binds to the stored width');
    });
  });

  // --- Barcode color (021 / US3) --------------------------------------------
  group('properties — barcode color (C1/C8)', () {
    Future<String> addBarcode(
        WidgetTester tester, JetReportDesignerController c) async {
      c.createElement(DesignerToolType.barcode,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      final String id = c.selection.singleOrNull!;
      await tester.pumpAndSettle();
      return id;
    }

    BarcodeElement barcodeOf(JetReportDesignerController c, String id) =>
        _elementById(c, id) as BarcodeElement;

    testWidgets('a barcode shows the color row; other types do not',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await addBarcode(tester, c);
      expect(_field('barcodeColor'), findsOneWidget);

      await _addText(tester, c);
      expect(_field('barcodeColor'), findsNothing);

      await _addShape(tester, c, at: const JetOffset(120, 30));
      expect(_field('barcodeColor'), findsNothing);
    });

    testWidgets('shows the current color and commits one setBarcodeColor',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await addBarcode(tester, c);

      // The compact swatch trigger shows the current color (no inline hex); a
      // new barcode is black.
      expect(_field('barcodeColor'), findsOneWidget);
      expect(barcodeOf(c, id).color, JetColor.black,
          reason: 'a new barcode is black');

      await tester.tap(_field('barcodeColor'));
      await tester.pumpAndSettle();
      await tester.tap(_field('barcodeColor.swatch.indigo'));
      await tester.pumpAndSettle();

      expect(barcodeOf(c, id).color, const JetColor(0xFF6366F1));
      c.undo();
      expect(barcodeOf(c, id).color, JetColor.black,
          reason: 'one-step undo restores black');
    });

    testWidgets('the barcode color editor offers no None entry (C8)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await addBarcode(tester, c);

      await tester.tap(_field('barcodeColor'));
      await tester.pumpAndSettle();
      expect(_field('barcodeColor.none'), findsNothing);
      expect(_field('barcodeColor.hex'), findsOneWidget);
    });
  });

  // --- Barcode inspector (036) -------------------------------------------
  group('properties — barcode inspector (036)', () {
    /// Pumps the designer with a controller pre-loaded with a barcode element
    /// with the given [id] and [symbology], selects it, and opens Properties.
    Future<JetReportDesignerController> pumpBarcode(
      WidgetTester tester, {
      required String id,
      BarcodeSymbology symbology = BarcodeSymbology.auto,
      String data = '1234567890',
      String? dataField,
      JetDataSchema? schema,
    }) async {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: ReportDefinition(
          name: 'Barcode',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'detail',
                  type: BandType.detail,
                  height: 120,
                  elements: <ReportElement>[
                    BarcodeElement(
                      id: id,
                      bounds:
                          const JetRect(x: 10, y: 10, width: 80, height: 80),
                      symbology: symbology,
                      data: data,
                      dataField: dataField,
                    ),
                  ],
                )),
              ],
            ),
          ),
        ),
      );
      // Note: pumpDesignerWith already registers addTearDown(c.dispose); do not
      // add a second teardown here or the controller will be disposed twice.
      await pumpDesignerWith(tester, controller: c, dataSchema: schema);
      await _openProperties(tester);
      c.select(id);
      await tester.pumpAndSettle();
      return c;
    }

    /// The selected barcode element in [c].
    BarcodeElement barcode(JetReportDesignerController c, String id) =>
        _elementById(c, id) as BarcodeElement;

    /// A one-field product schema for exercising the Data field picker.
    final JetDataSchema productSchema = JetDataSchema(
      name: 'Products',
      fields: <FieldDef>[FieldDef('sku', type: JetFieldType.string)],
    );

    testWidgets('barcode inspector shows symbology + data + options',
        (WidgetTester tester) async {
      await pumpBarcode(tester, id: 'b1');
      expect(find.text('Symbology'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Show text'), findsOneWidget);
      expect(find.text('Quiet zone'), findsOneWidget);
    });

    testWidgets('ECC row only appears for QR', (WidgetTester tester) async {
      await pumpBarcode(tester, id: 'b1', symbology: BarcodeSymbology.qrCode);
      expect(find.text('Error correction'), findsOneWidget);

      await pumpBarcode(tester, id: 'b2', symbology: BarcodeSymbology.code128);
      expect(find.text('Error correction'), findsNothing);
    });

    testWidgets('show-text row absent for 2D symbology (QR)',
        (WidgetTester tester) async {
      await pumpBarcode(tester, id: 'b1', symbology: BarcodeSymbology.qrCode);
      expect(find.text('Show text'), findsNothing);
    });

    testWidgets('show-text row present for 1D symbology (Code 128)',
        (WidgetTester tester) async {
      await pumpBarcode(tester, id: 'b1', symbology: BarcodeSymbology.code128);
      expect(find.text('Show text'), findsOneWidget);
    });

    testWidgets('auto mode with 1D literal still shows show-text + no ECC',
        (WidgetTester tester) async {
      // '1234567890' → code128 (10 digits, not 8/12/13/14) → 1D
      await pumpBarcode(tester,
          id: 'b1', symbology: BarcodeSymbology.auto, data: '1234567890');
      expect(find.text('Show text'), findsOneWidget);
      expect(find.text('Error correction'), findsNothing);
    });

    testWidgets('a literal invalid for a pinned symbology shows the hint',
        (WidgetTester tester) async {
      // 'ABC' is not valid EAN-13 (needs 12/13 digits) → invalid-value hint.
      await pumpBarcode(tester,
          id: 'b1', symbology: BarcodeSymbology.ean13, data: 'ABC');
      expect(
          find.text('Value is not valid for this symbology'), findsOneWidget);
    });

    testWidgets('a valid literal shows no invalid hint',
        (WidgetTester tester) async {
      await pumpBarcode(tester,
          id: 'b1', symbology: BarcodeSymbology.code128, data: 'HELLO');
      expect(find.text('Value is not valid for this symbology'), findsNothing);
    });

    // --- Data: one field-or-literal input, no Literal/Field switch ----------
    testWidgets('the Data input is one field, with no Literal/Field switch',
        (WidgetTester tester) async {
      await pumpBarcode(tester, id: 'b1', data: 'HELLO');
      // One unified value-style input showing the literal.
      expect(_field('barcodeData.b1'), findsOneWidget);
      expect(_valueIn('barcodeData.b1', 'HELLO'), findsOneWidget);
      // The old literal↔field toggle is gone.
      expect(find.text('Literal'), findsNothing);
      expect(find.text('Field'), findsNothing);
    });

    testWidgets('typing a [field] token binds the data field',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await pumpBarcode(tester, id: 'b1', data: 'HELLO');
      await tester.enterText(_editable('barcodeData.b1'), '[sku]');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(barcode(c, 'b1').dataField, 'sku');
    });

    testWidgets('typing plain text sets a literal and clears the binding',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          await pumpBarcode(tester, id: 'b1', data: '', dataField: 'sku');
      await tester.enterText(_editable('barcodeData.b1'), '9501101530003');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(barcode(c, 'b1').data, '9501101530003');
      expect(barcode(c, 'b1').dataField, isNull);
    });

    testWidgets('a bound field shows its [field] token in the input',
        (WidgetTester tester) async {
      await pumpBarcode(tester,
          id: 'b1', data: '', dataField: 'sku', schema: productSchema);
      expect(_valueIn('barcodeData.b1', '[sku]'), findsOneWidget);
    });

    testWidgets('the field picker inserts a [field] binding (no fx button)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpBarcode(tester,
          id: 'b1', data: 'HELLO', schema: productSchema);
      // No expression affordance — barcode is field-or-literal.
      expect(find.byKey(const ValueKey<String>('$_p.field.value.fx')),
          findsNothing);
      // The field picker is present; tapping it and choosing a field binds it.
      final Finder pick =
          find.byKey(const ValueKey<String>('$_p.field.barcodeData.pick'));
      expect(pick, findsOneWidget);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('$_p.field.barcodeData.pick.sku')));
      await tester.pumpAndSettle();
      expect(barcode(c, 'b1').dataField, 'sku');
    });
  });

  // --- Shape gallery (020 / US1) -------------------------------------------
  group('properties — shape gallery', () {
    testWidgets('shows the Shape section with the seven closed forms (C1.1)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addShape(tester, c);

      for (final String form in _shapeForms) {
        expect(_shapeThumb(form), findsOneWidget, reason: '$form thumbnail');
      }
      // The legacy diagonal line is not offered as an authoring form.
      expect(_shapeThumb('line'), findsNothing);
    });

    testWidgets('no gallery for a text element (C1.2 / FR-010)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addText(tester, c);

      expect(_shapeThumb('rectangle'), findsNothing);
      expect(_shapeThumb('hexagon'), findsNothing);
    });

    testWidgets('no gallery with nothing or several selected (C1.3 / FR-010)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      // Nothing selected.
      expect(_shapeThumb('rectangle'), findsNothing);
      // Multi-selection: two shapes selected together fall through to empty.
      await _addShape(tester, c, at: const JetOffset(10, 10));
      await _addShape(tester, c, at: const JetOffset(120, 10));
      c.selectAll();
      await tester.pumpAndSettle();
      expect(_shapeThumb('rectangle'), findsNothing);
    });

    testWidgets('the active form is the only highlighted thumbnail (C2.1)',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addShape(tester, c); // a rectangle

      for (final String form in _shapeForms) {
        expect(
          tester.getSemantics(_shapeThumb(form)),
          isSemantics(isSelected: form == 'rectangle'),
          reason: 'only the active rectangle is highlighted, not $form',
        );
      }
      sem.dispose();
    });

    testWidgets('an unknown-form shape highlights nothing (C2.2 / FR-009)',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      // A shape loaded with an unrecognized form renders as rectangle but must
      // not present rectangle as a deliberate choice.
      final JetReportDesignerController c = JetReportDesignerController(
        definition: const ReportDefinition(
          name: 'U',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'detail',
                    type: BandType.detail,
                    height: 120,
                    elements: <ReportElement>[
                      ShapeElement(
                        id: 's',
                        bounds: JetRect(x: 5, y: 5, width: 60, height: 40),
                        kind: ShapeKind.rectangle,
                        unknownForm: 'octagon',
                      ),
                    ])),
              ],
            ),
          ),
        ),
      );
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.select('s');
      await tester.pumpAndSettle();

      for (final String form in _shapeForms) {
        expect(
          tester.getSemantics(_shapeThumb(form)),
          isSemantics(isSelected: false),
          reason: '$form must not be highlighted for an unknown form',
        );
      }
      sem.dispose();
    });

    testWidgets(
        'clicking a thumbnail changes the form, preserving the box '
        '(C3.1–C3.3)', (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c);
      final JetRect before = _shapeOf(c, id).bounds;
      final JetBoxStyle style = _shapeOf(c, id).style;

      await tester.tap(_shapeThumb('hexagon'));
      await tester.pumpAndSettle();

      expect(_shapeOf(c, id).kind, ShapeKind.hexagon);
      expect(_shapeOf(c, id).bounds, before, reason: 'geometry preserved');
      expect(_shapeOf(c, id).style, style, reason: 'style preserved');
    });

    testWidgets('a shape can switch between forms and back via the UI (C5.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addShape(tester, c); // a rectangle

      await tester.tap(_shapeThumb('star'));
      await tester.pumpAndSettle();
      expect(_shapeOf(c, id).kind, ShapeKind.star);

      await tester.tap(_shapeThumb('rectangle'));
      await tester.pumpAndSettle();
      expect(_shapeOf(c, id).kind, ShapeKind.rectangle);
    });
  });
}
