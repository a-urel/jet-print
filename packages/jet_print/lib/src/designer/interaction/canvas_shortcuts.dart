/// Keyboard shortcuts scoped to the design canvas's focus.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/jet_report_designer_controller.dart';

/// Intent: undo the last edit.
class UndoIntent extends Intent {
  /// Const constructor.
  const UndoIntent();
}

/// Intent: redo the last undone edit.
class RedoIntent extends Intent {
  /// Const constructor.
  const RedoIntent();
}

/// Intent: delete the selection.
class DeleteSelectionIntent extends Intent {
  /// Const constructor.
  const DeleteSelectionIntent();
}

/// Intent: copy / cut / paste / duplicate / select-all / clear.
class CopyIntent extends Intent {
  /// Const constructor.
  const CopyIntent();
}

/// Intent: cut the selection.
class CutIntent extends Intent {
  /// Const constructor.
  const CutIntent();
}

/// Intent: paste the clipboard.
class PasteIntent extends Intent {
  /// Const constructor.
  const PasteIntent();
}

/// Intent: duplicate the selection.
class DuplicateIntent extends Intent {
  /// Const constructor.
  const DuplicateIntent();
}

/// Intent: select all elements.
class SelectAllIntent extends Intent {
  /// Const constructor.
  const SelectAllIntent();
}

/// Intent: clear the selection (Escape).
class ClearSelectionIntent extends Intent {
  /// Const constructor.
  const ClearSelectionIntent();
}

/// Intent: zoom in.
class ZoomInIntent extends Intent {
  /// Const constructor.
  const ZoomInIntent();
}

/// Intent: zoom out.
class ZoomOutIntent extends Intent {
  /// Const constructor.
  const ZoomOutIntent();
}

/// Intent: fit the page to the viewport.
class ZoomFitIntent extends Intent {
  /// Const constructor.
  const ZoomFitIntent();
}

/// Intent: nudge the selection by ([dx], [dy]) points.
class NudgeIntent extends Intent {
  /// Const constructor.
  const NudgeIntent(this.dx, this.dy);

  /// Horizontal nudge in points.
  final double dx;

  /// Vertical nudge in points.
  final double dy;
}

const double _n = 1; // fine nudge (pt)
const double _c = 10; // coarse nudge (Shift, pt)

/// Wraps [child] with the designer's keyboard shortcuts, bound to [controller].
///
/// The bindings live in a [Shortcuts] widget *above the canvas focus only*, so
/// they fire when the canvas is focused but not while a panel input has focus —
/// typing in a Properties field never triggers them (focus-scoped shortcuts).
/// Both ⌘ (macOS) and Ctrl are bound for clipboard/undo/redo/select-all.
class CanvasShortcuts extends StatelessWidget {
  /// Wraps [child] with the canvas shortcuts.
  const CanvasShortcuts(
      {required this.controller, required this.child, super.key});

  /// The controller the shortcuts drive.
  final JetReportDesignerController controller;

  /// The focusable canvas subtree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        // History.
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            RedoIntent(),
        // Clipboard + selection.
        SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopyIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true): CopyIntent(),
        SingleActivator(LogicalKeyboardKey.keyX, meta: true): CutIntent(),
        SingleActivator(LogicalKeyboardKey.keyX, control: true): CutIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, control: true): PasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, meta: true): DuplicateIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: true):
            DuplicateIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, meta: true): SelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            SelectAllIntent(),
        // Delete + escape.
        SingleActivator(LogicalKeyboardKey.delete): DeleteSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): DeleteSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.escape): ClearSelectionIntent(),
        // Zoom.
        SingleActivator(LogicalKeyboardKey.equal, meta: true): ZoomInIntent(),
        SingleActivator(LogicalKeyboardKey.equal, control: true):
            ZoomInIntent(),
        SingleActivator(LogicalKeyboardKey.minus, meta: true): ZoomOutIntent(),
        SingleActivator(LogicalKeyboardKey.minus, control: true):
            ZoomOutIntent(),
        SingleActivator(LogicalKeyboardKey.digit0, meta: true): ZoomFitIntent(),
        SingleActivator(LogicalKeyboardKey.digit0, control: true):
            ZoomFitIntent(),
        // Nudge (arrows; Shift = coarse).
        SingleActivator(LogicalKeyboardKey.arrowLeft): NudgeIntent(-_n, 0),
        SingleActivator(LogicalKeyboardKey.arrowRight): NudgeIntent(_n, 0),
        SingleActivator(LogicalKeyboardKey.arrowUp): NudgeIntent(0, -_n),
        SingleActivator(LogicalKeyboardKey.arrowDown): NudgeIntent(0, _n),
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            NudgeIntent(-_c, 0),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            NudgeIntent(_c, 0),
        SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            NudgeIntent(0, -_c),
        SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            NudgeIntent(0, _c),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          UndoIntent: _cb<UndoIntent>((_) => controller.undo()),
          RedoIntent: _cb<RedoIntent>((_) => controller.redo()),
          DeleteSelectionIntent:
              _cb<DeleteSelectionIntent>((_) => controller.delete()),
          CopyIntent: _cb<CopyIntent>((_) => controller.copy()),
          CutIntent: _cb<CutIntent>((_) => controller.cut()),
          PasteIntent: _cb<PasteIntent>((_) => controller.paste()),
          DuplicateIntent: _cb<DuplicateIntent>((_) => controller.duplicate()),
          SelectAllIntent: _cb<SelectAllIntent>((_) => controller.selectAll()),
          ClearSelectionIntent:
              _cb<ClearSelectionIntent>((_) => controller.clearSelection()),
          ZoomInIntent: _cb<ZoomInIntent>((_) => controller.zoomIn()),
          ZoomOutIntent: _cb<ZoomOutIntent>((_) => controller.zoomOut()),
          ZoomFitIntent: _cb<ZoomFitIntent>((_) => controller.fitToView()),
          NudgeIntent:
              _cb<NudgeIntent>((NudgeIntent i) => controller.nudge(i.dx, i.dy)),
        },
        child: child,
      ),
    );
  }

  CallbackAction<T> _cb<T extends Intent>(void Function(T intent) run) =>
      CallbackAction<T>(onInvoke: (T intent) {
        run(intent);
        return null;
      });
}
