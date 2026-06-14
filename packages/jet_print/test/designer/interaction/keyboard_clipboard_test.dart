// US4 keyboard + clipboard shortcuts (T055 / FR-013/014/015/016), scoped to the
// canvas focus.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _toolFinder(DesignerToolType type) =>
    find.byKey(ValueKey<String>('jet_print.designer.tool.${type.name}'));

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

/// Enumerates every band in [def]'s reified tree (furniture slots, body
/// title/summary/noData, and the detail tree's group headers/footers and
/// per-row/nested bands), so the element-count assertions still span the whole
/// design — the reified replacement for the old flat `template.bands`.
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

Iterable<ReportElement> _allElements(JetReportDesignerController c) =>
    _bands(c.definition).expand((Band b) => b.elements);

int _count(JetReportDesignerController c) => _allElements(c).length;

Future<void> _meta(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

/// Creates a text element and gives the canvas focus (so shortcuts fire).
Future<String> _createAndFocus(
    WidgetTester tester, JetReportDesignerController c) async {
  await tester.tap(_toolFinder(DesignerToolType.text));
  await tester.pumpAndSettle();
  final String id = c.selection.singleOrNull!;
  await tester.tapAt(tester.getCenter(_elementFinder(id)));
  await tester.pumpAndSettle();
  return id;
}

void main() {
  testWidgets('arrow keys nudge the selection by 1 pt',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final String id = await _createAndFocus(tester, controller);
    final double x0 = _allElements(controller)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds
        .x;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    final double x1 = _allElements(controller)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds
        .x;
    expect(x1, x0 + 1);
  });

  testWidgets('Delete removes the selection', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await _createAndFocus(tester, controller);
    expect(_count(controller), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(_count(controller), 0);
  });

  testWidgets('⌘C / ⌘V copy and paste; ⌘D duplicates; ⌘A selects all',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await _createAndFocus(tester, controller);

    await _meta(tester, LogicalKeyboardKey.keyC); // copy
    await _meta(tester, LogicalKeyboardKey.keyV); // paste
    expect(_count(controller), 2);

    await _meta(tester, LogicalKeyboardKey.keyD); // duplicate selection
    expect(_count(controller), 3);

    await _meta(tester, LogicalKeyboardKey.keyA); // select all
    expect(controller.selection.length, 3);
  });
}
