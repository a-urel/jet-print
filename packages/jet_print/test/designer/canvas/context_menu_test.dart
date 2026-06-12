// Canvas context menu (016 / US2 / C3): a right-click menu (Cut, Copy, Paste,
// Duplicate, Delete) that resolves selection per FR-010 BEFORE it opens, reads
// the same canCopy/canPaste predicates as the toolbar (FR-012), and acts through
// the existing controller ops (FR-003).
//
// Drives the public designer through a supplied controller; finds elements and
// menu items by their stable widget keys (the canvas gesture detector owns
// hit-testing, so the per-element regions are non-capturing test hooks).
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/designer_harness.dart';

const Key _menuRegionKey =
    ValueKey<String>('jet_print.designer.canvas.contextMenu');
const Key _cutKey = ValueKey<String>('jet_print.designer.menu.cut');
const Key _copyKey = ValueKey<String>('jet_print.designer.menu.copy');
const Key _pasteKey = ValueKey<String>('jet_print.designer.menu.paste');
const Key _duplicateKey = ValueKey<String>('jet_print.designer.menu.duplicate');
const Key _deleteKey = ValueKey<String>('jet_print.designer.menu.delete');

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

int _elementCount(JetReportDesignerController c) => c.template.bands
    .fold<int>(0, (int n, ReportBand b) => n + b.elements.length);

bool _menuEnabled(WidgetTester tester, Key key) =>
    tester.widget<ShadContextMenuItem>(find.byKey(key)).enabled;

ReportTemplate _twoElementFixture() => const ReportTemplate(
      name: 'F',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 300,
          elements: <ReportElement>[
            TextElement(
                id: 'a',
                bounds: JetRect(x: 20, y: 20, width: 80, height: 24),
                text: 'a'),
            TextElement(
                id: 'b',
                bounds: JetRect(x: 20, y: 120, width: 80, height: 24),
                text: 'b'),
          ],
        ),
      ],
    );

/// Pumps the designer over the two-element fixture and returns the controller.
Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController c = JetReportDesignerController()
    ..open(_twoElementFixture());
  await pumpDesignerWith(tester, controller: c);
  return c;
}

/// Right-clicks the element [id] (secondary tap at its centre).
Future<void> _secondaryTapElement(WidgetTester tester, String id) async {
  await tester.tapAt(tester.getCenter(_elementFinder(id)),
      buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

/// Right-clicks an empty spot in the canvas margin (left of the page).
Future<void> _secondaryTapEmpty(WidgetTester tester) async {
  final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
  await tester.tapAt(Offset(pageTopLeft.dx - 8, pageTopLeft.dy + 120),
      buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click an element opens the menu and selects it (2.1)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    expect(c.selection.isEmpty, isTrue);

    expect(find.byKey(_menuRegionKey), findsOneWidget);
    await _secondaryTapElement(tester, 'a');

    // Selection resolved BEFORE the menu opened (FR-010), and the menu is up.
    expect(c.selection.singleOrNull, 'a');
    expect(find.byKey(_cutKey), findsOneWidget);
    expect(find.byKey(_copyKey), findsOneWidget);
    expect(find.byKey(_pasteKey), findsOneWidget);
    expect(find.byKey(_duplicateKey), findsOneWidget);
    expect(find.byKey(_deleteKey), findsOneWidget);
  });

  testWidgets('menu Copy then menu Paste inserts a selected offset copy (2.2)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    await _secondaryTapElement(tester, 'a');
    await tester.tap(find.byKey(_copyKey));
    await tester.pumpAndSettle();
    expect(_elementCount(c), 2, reason: 'Copy does not change the document');

    await _secondaryTapElement(tester, 'a');
    await tester.tap(find.byKey(_pasteKey));
    await tester.pumpAndSettle();

    expect(_elementCount(c), 3); // SC-002
    expect(c.selection.singleOrNull, isNotNull);
    expect(c.selection.singleOrNull, isNot('a'));
  });

  testWidgets('empty canvas, nothing selected ⇒ Cut/Copy disabled (2.3)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    expect(c.canPaste, isFalse);

    await _secondaryTapEmpty(tester);

    expect(_menuEnabled(tester, _cutKey), isFalse);
    expect(_menuEnabled(tester, _copyKey), isFalse);
    expect(_menuEnabled(tester, _duplicateKey), isFalse);
    expect(_menuEnabled(tester, _deleteKey), isFalse);
    // Paste is disabled because the clipboard is empty.
    expect(_menuEnabled(tester, _pasteKey), isFalse);
  });

  testWidgets('empty canvas ⇒ Paste enabled when the clipboard has content',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.select('a');
    c.copy(); // fills the clipboard
    await tester.pumpAndSettle();

    await _secondaryTapEmpty(tester);
    expect(_menuEnabled(tester, _pasteKey), isTrue);
  });

  testWidgets('multi-select then right-click empty preserves selection (2.6)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.selectElements(<String>['a', 'b']);
    await tester.pumpAndSettle();

    await _secondaryTapEmpty(tester);
    // Right-click on empty canvas must NOT deselect (FR-010, clarified).
    expect(c.selection.ids.toSet(), <String>{'a', 'b'});

    // Cut acts on both elements.
    await tester.tap(find.byKey(_cutKey));
    await tester.pumpAndSettle();
    expect(_elementCount(c), 0);
  });

  testWidgets('right-click an unselected element replaces the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.select('a');
    await tester.pumpAndSettle();

    await _secondaryTapElement(tester, 'b');
    // The clicked element becomes the (single) selection (edge case).
    expect(c.selection.singleOrNull, 'b');
  });

  testWidgets('dismissing the menu makes no document change (2.4 / FR-011)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    final int before = _elementCount(c);

    await _secondaryTapElement(tester, 'a');
    expect(find.byKey(_cutKey), findsOneWidget);

    // Tap away (primary) to dismiss without acting.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byKey(_cutKey), findsNothing, reason: 'menu dismissed');
    expect(_elementCount(c), before, reason: 'no document change on dismiss');
  });

  testWidgets('menu Duplicate inserts a selected offset copy in one step (2.5)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    await _secondaryTapElement(tester, 'a');
    await tester.tap(find.byKey(_duplicateKey));
    await tester.pumpAndSettle();

    expect(_elementCount(c), 3);
    expect(c.selection.singleOrNull, isNot('a'));
    // One undoable step restores the original document.
    c.undo();
    expect(_elementCount(c), 2);
  });

  testWidgets('menu Delete removes the selection in one step (2.5)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    await _secondaryTapElement(tester, 'a');
    await tester.tap(find.byKey(_deleteKey));
    await tester.pumpAndSettle();

    expect(_elementCount(c), 1);
    c.undo();
    expect(_elementCount(c), 2);
  });
}
