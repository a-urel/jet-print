// US3 controls (T050): the top-bar Undo/Redo buttons reflect canUndo/canRedo
// and drive the controller; ⌘Z / ⇧⌘Z act when the canvas is focused.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/designer_harness.dart';

final Finder _undoButton =
    find.byKey(const ValueKey<String>('jet_print.designer.action.undo'));
final Finder _redoButton =
    find.byKey(const ValueKey<String>('jet_print.designer.action.redo'));

Finder _toolFinder(DesignerToolType type) =>
    find.byKey(ValueKey<String>('jet_print.designer.tool.${type.name}'));

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

bool _disabled(WidgetTester tester, Finder f) =>
    tester.widget<ShadIconButton>(f).onPressed == null;

/// Total element count across [c]'s reified tree (furniture, body
/// title/summary/noData, and the detail tree's group + per-row/nested bands) —
/// the reified replacement for the old flat `template.bands` fold.
Iterable<Band> _bands(ReportDefinition def) sync* {
  final PageFurniture f = def.furniture;
  for (final Band? b in <Band?>[
    f.background,
    f.pageHeader,
    f.columnHeader,
    f.columnFooter,
    f.pageFooter,
  ]) {
    if (b != null) yield b;
  }
  final ReportBody body = def.body;
  for (final Band? b in <Band?>[body.title, body.summary, body.noData]) {
    if (b != null) yield b;
  }
  yield* _scopeBands(body.root);
}

Iterable<Band> _scopeBands(DetailScope scope) sync* {
  for (final GroupLevel g in scope.groups) {
    if (g.header != null) yield g.header!;
  }
  for (final ScopeNode node in scope.children) {
    switch (node) {
      case BandNode(:final Band band):
        yield band;
      case NestedScope(:final DetailScope scope):
        yield* _scopeBands(scope);
    }
  }
  for (final GroupLevel g in scope.groups) {
    if (g.footer != null) yield g.footer!;
  }
}

int _count(JetReportDesignerController c) =>
    _bands(c.definition).fold<int>(0, (int n, Band b) => n + b.elements.length);

void main() {
  testWidgets('undo/redo buttons reflect availability and drive the controller',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);

    // Nothing to undo/redo yet → both disabled.
    expect(_disabled(tester, _undoButton), isTrue);
    expect(_disabled(tester, _redoButton), isTrue);

    await tester.tap(_toolFinder(DesignerToolType.text));
    await tester.pumpAndSettle();
    expect(_count(controller), 1);
    // Undo becomes available; redo still disabled.
    expect(_disabled(tester, _undoButton), isFalse);
    expect(_disabled(tester, _redoButton), isTrue);

    await tester.tap(_undoButton);
    await tester.pumpAndSettle();
    expect(_count(controller), 0);
    // Now redo is available.
    expect(_disabled(tester, _redoButton), isFalse);

    await tester.tap(_redoButton);
    await tester.pumpAndSettle();
    expect(_count(controller), 1);
  });

  testWidgets('⌘Z undoes and ⇧⌘Z redoes when the canvas is focused',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(_count(controller), 1);

    // Focus the canvas by tapping the element.
    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    await tester.pumpAndSettle();

    // ⌘Z → undo.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(_count(controller), 0);

    // ⇧⌘Z → redo.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(_count(controller), 1);
  });
}
