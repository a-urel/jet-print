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
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _emptyHint = find.byKey(const ValueKey<String>('$_p.empty'));
Finder _field(String name) => find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));
Finder _valueIn(String name, String text) =>
    find.descendant(of: _field(name), matching: find.text(text));

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
double _previewAspect(WidgetTester tester) => tester
    .widget<AspectRatio>(
        find.descendant(of: _preview, matching: find.byType(AspectRatio)))
    .aspectRatio;

/// A report whose page is exactly [w] × [h] points (default margins), so the
/// PAGE controls can be driven against a known size.
ReportTemplate _pageTemplate(double w, double h) => ReportTemplate(
      name: 'Page',
      page: PageFormat(
          width: w, height: h, margins: const JetEdgeInsets.all(28.35)),
      bands: const <ReportBand>[ReportBand(type: BandType.detail, height: 100)],
    );

JetRect _bounds(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

String _text(JetReportDesignerController c, String id) => (c.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement e) => e.id == id) as TextElement)
    .text;

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<String> _addText(WidgetTester tester, JetReportDesignerController c,
    {JetOffset at = const JetOffset(20, 30)}) async {
  c.createElement(DesignerToolType.text, bandIndex: 1, at: at);
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  return id;
}

/// Adds a default (rectangle) shape, selects it, and returns its id (020).
Future<String> _addShape(WidgetTester tester, JetReportDesignerController c,
    {JetOffset at = const JetOffset(20, 30)}) async {
  c.createElement(DesignerToolType.shape, bandIndex: 1, at: at);
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  return id;
}

ShapeElement _shapeOf(JetReportDesignerController c, String id) =>
    c.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement e) => e.id == id) as ShapeElement;

JetTextStyle _textStyleOf(JetReportDesignerController c, String id) =>
    (c.template.bands
            .expand((ReportBand b) => b.elements)
            .firstWhere((ReportElement e) => e.id == id) as TextElement)
        .style;

/// The controller's history revision — unchanged across an interaction ⇔ that
/// interaction recorded no undo entry (no-op commits must not pollute history).
int _undoDepth(JetReportDesignerController c) => c.revision;

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
          bandIndex: 1, at: const JetOffset(10, 10));
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
      c.selectBand(1); // detail, height 200
      await tester.pumpAndSettle();

      expect(_valueIn('bandHeight', '200'), findsOneWidget);
      await tester.enterText(_editable('bandHeight'), '260');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.template.bands[1].height, 260);
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
      final JetReportDesignerController c =
          JetReportDesignerController(template: _pageTemplate(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      // The Name field is present and reflects the live template name.
      expect(_field('reportName'), findsOneWidget);
      expect(_valueIn('reportName', 'Page'), findsOneWidget);
    });

    testWidgets('editing the Name renames the report (one undoable step)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(template: _pageTemplate(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.enterText(_editable('reportName'), 'Invoice');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.template.name, 'Invoice');

      // Exactly one history entry: undo restores the prior name.
      c.undo();
      expect(c.template.name, 'Page');
    });

    testWidgets('a blank Name reverts, keeping the report named',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(template: _pageTemplate(595.28, 841.89));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      await tester.enterText(_editable('reportName'), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.template.name, 'Page', reason: 'blank entry is not committed');
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

      // The default A4 page is named, not shown as raw numbers (C1.1).
      expect(find.descendant(of: _field('paper'), matching: find.text('A4')),
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
      final JetEdgeInsets marginsBefore = c.template.page.margins;

      await tester.tap(_field('paper'));
      await tester.pumpAndSettle();
      await tester.tap(_paperOption('Letter'));
      await tester.pumpAndSettle();

      expect(c.template.page.width, 612);
      expect(c.template.page.height, 792);
      expect(c.template.page.margins, marginsBefore,
          reason: 'changing paper type leaves margins untouched');
      // The picker now reflects the new size by name.
      expect(
          find.descendant(of: _field('paper'), matching: find.text('Letter')),
          findsOneWidget);
    });

    testWidgets('a page matching no preset reads Custom (C1.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(template: _pageTemplate(500, 700));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      expect(
          find.descendant(of: _field('paper'), matching: find.text('Custom')),
          findsOneWidget);
      // Dimensions are unaltered by recognition.
      expect(c.template.page.width, 500);
      expect(c.template.page.height, 700);
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

      expect(c.template.page.margins, const JetEdgeInsets.all(14.17));
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

      expect(c.template.page.margins.left, 50);
      expect(c.template.page.margins.top, 28.35);
      expect(c.template.page.margins.right, 28.35);
      expect(c.template.page.margins.bottom, 28.35);
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
      final double before = c.template.page.margins.left;

      await tester.enterText(_editable('marginLeft'), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.template.page.margins.left, before,
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
      final double w = c.template.page.width;
      final double h = c.template.page.height;

      await tester.tap(find
          .byKey(const ValueKey<String>('$_p.field.orientation.landscape')));
      await tester.pumpAndSettle();

      expect(c.template.page.width, h);
      expect(c.template.page.height, w);
      expect(_previewAspect(tester), greaterThan(1)); // now landscape
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

      expect(c.template.page.width, 300);
      expect(c.template.page.height, 500);
    });

    testWidgets('a custom dimension field reverts invalid input (C3.5)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(template: _pageTemplate(300, 500));
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();
      expect(_field('pageWidth'), findsOneWidget); // 300×500 is custom

      await tester.enterText(_editable('pageWidth'), 'xyz');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(c.template.page.width, 300, reason: 'invalid input is rejected');
    });
  });

  // --- Number-field clamping (021 / foundational, contract C4) --------------
  //
  // The clamp contract is parameterized over the two ranged fields this feature
  // introduces: font size [4, 144] (here) and outline width [0, 20] (in the
  // shape-appearance group). Both ride the same _NumberField primitive.
  group('properties — number-field clamping (C4)', () {
    testWidgets('an out-of-range font size commits the clamped bound',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      await tester.enterText(_editable('fontSize'), '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, id).fontSize, 144, reason: 'clamped to max');

      await tester.enterText(_editable('fontSize'), '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, id).fontSize, 4, reason: 'clamped to min');
    });

    testWidgets('non-numeric input is rejected, restored, and not committed',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      final int undoDepthBefore = _undoDepth(c);

      await tester.enterText(_editable('fontSize'), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_textStyleOf(c, id).fontSize, 12, reason: 'invalid is rejected');
      expect(find.text('abc'), findsNothing);
      expect(_valueIn('fontSize', '12'), findsOneWidget,
          reason: 'the field restores the last valid value');
      expect(_undoDepth(c), undoDepthBefore, reason: 'no history entry');
    });

    testWidgets('the stepper at a bound stays at the bound as a no-op',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      await tester.enterText(_editable('fontSize'), '144');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_textStyleOf(c, id).fontSize, 144);
      final int undoDepthBefore = _undoDepth(c);

      await tester.tap(find.descendant(
          of: _field('fontSize'),
          matching: find.byIcon(LucideIcons.chevronUp)));
      await tester.pumpAndSettle();

      expect(_textStyleOf(c, id).fontSize, 144, reason: 'stays at the bound');
      expect(_undoDepth(c), undoDepthBefore,
          reason: 'a bound-stuck bump records no history');
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
        template: ReportTemplate(
          name: 'U',
          page: PageFormat.a4Portrait,
          bands: const <ReportBand>[
            ReportBand(
                type: BandType.detail,
                height: 120,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 's',
                    bounds: JetRect(x: 5, y: 5, width: 60, height: 40),
                    kind: ShapeKind.rectangle,
                    unknownForm: 'octagon',
                  ),
                ]),
          ],
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
