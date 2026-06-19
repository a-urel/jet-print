// Designer-wide undo/redo: ⌘Z / ⇧⌘Z (Ctrl on Windows/Linux) act from anywhere
// in the designer — a panel, the outline, a toolbar button — not only when the
// canvas is focused. The one exception is a focused text input, where ⌘Z must
// keep undoing *typing* rather than the document.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _toolFinder(DesignerToolType type) =>
    find.byKey(ValueKey<String>('jet_print.designer.tool.${type.name}'));

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

Future<void> _meta(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('⌘Z undoes / ⇧⌘Z redoes without the canvas ever being focused',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    expect(_count(controller), 1);

    // The canvas was never tapped, so focus rests on the designer shell — with
    // the old canvas-scoped binding ⌘Z here would do nothing.
    await _meta(tester, LogicalKeyboardKey.keyZ);
    expect(_count(controller), 0);

    await _meta(tester, LogicalKeyboardKey.keyZ, shift: true); // redo
    expect(_count(controller), 1);
  });

  testWidgets('⌘Z in a Properties text field undoes typing, not the document',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.text));
    await tester.pumpAndSettle();
    expect(_count(controller), 1); // canUndo is now true

    await openPropertiesTab(tester);
    final Finder field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.pumpAndSettle();

    await _meta(tester, LogicalKeyboardKey.keyZ);

    // The text field swallowed ⌘Z (it undoes typing); the document is untouched.
    expect(_count(controller), 1);
  });
}
