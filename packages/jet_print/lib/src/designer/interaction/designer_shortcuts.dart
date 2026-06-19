/// Designer-wide undo/redo shortcuts, scoped to the whole designer shell.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/jet_report_designer_controller.dart';
import 'canvas_shortcuts.dart' show RedoIntent, UndoIntent;

/// Wraps [child] with undo/redo shortcuts that fire from *anywhere* in the
/// designer, bound to [controller].
///
/// Unlike [CanvasShortcuts] (focus-scoped to the canvas), these bindings live
/// above an autofocusing [FocusScope], so focus rests inside the designer's own
/// subtree by default and after non-focusing clicks — letting ⌘Z / ⌘⇧Z (Ctrl on
/// Windows/Linux) undo and redo whether the canvas, a panel, the outline, or a
/// toolbar button holds focus.
///
/// The one exception is a focused text input: there ⌘Z must undo *typing*, so
/// the actions disable themselves while an [EditableText] holds primary focus,
/// letting the key fall through to Flutter's DefaultTextEditingShortcuts. The
/// actions also stand down when there is nothing to undo/redo, so the keystroke
/// is never swallowed needlessly.
class DesignerShortcuts extends StatelessWidget {
  /// Wraps [child] with the designer-wide shortcuts.
  const DesignerShortcuts(
      {required this.controller, required this.child, super.key});

  /// The controller the shortcuts drive.
  final JetReportDesignerController controller;

  /// The designer shell subtree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          UndoIntent: _HistoryAction<UndoIntent>(
              controller,
              (JetReportDesignerController c) => c.undo(),
              (JetReportDesignerController c) => c.canUndo),
          RedoIntent: _HistoryAction<RedoIntent>(
              controller,
              (JetReportDesignerController c) => c.redo(),
              (JetReportDesignerController c) => c.canRedo),
        },
        child: FocusScope(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

/// An undo/redo [Action] that yields to text editing and to an empty history.
///
/// It disables itself while an [EditableText] holds focus (so ⌘Z there undoes
/// typing) and while [available] is false (nothing to undo/redo), so in both
/// cases the key event falls through to a more appropriate handler instead of
/// being consumed.
class _HistoryAction<T extends Intent> extends Action<T> {
  _HistoryAction(this.controller, this.run, this.available);

  final JetReportDesignerController controller;
  final void Function(JetReportDesignerController controller) run;
  final bool Function(JetReportDesignerController controller) available;

  @override
  bool isEnabled(T intent) => !_editableHasFocus() && available(controller);

  @override
  bool consumesKey(T intent) => isEnabled(intent);

  @override
  Object? invoke(T intent) {
    run(controller);
    return null;
  }
}

/// Whether an [EditableText] (a text field) currently holds primary focus, in
/// which case undo/redo must defer to the text field's own editing history.
bool _editableHasFocus() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  bool found = false;
  context.visitAncestorElements((Element element) {
    if (element.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
