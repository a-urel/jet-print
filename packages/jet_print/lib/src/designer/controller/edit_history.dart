/// Unbounded in-session undo/redo over immutable document snapshots.
library;

import 'designer_document.dart';

/// Two snapshot stacks implementing unlimited session undo/redo (FR-017).
///
/// On each committed edit the controller [push]es the *prior* document; that
/// clears the redo stack (a new edit invalidates any undone future, US3.3).
/// [undo]/[redo] move the current document across the two stacks. [revision]
/// increments on every change so the canvas painter's `shouldRepaint` can cheaply
/// detect that the committed model changed and rebuild its cached picture (D5).
class EditHistory {
  final List<DesignerDocument> _undo = <DesignerDocument>[];
  final List<DesignerDocument> _redo = <DesignerDocument>[];
  int _revision = 0;

  /// A monotonically increasing counter bumped on every history change.
  int get revision => _revision;

  /// Whether there is anything to undo.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is anything to redo.
  bool get canRedo => _redo.isNotEmpty;

  /// Records [previous] as an undo point and discards the redo stack.
  void push(DesignerDocument previous) {
    _undo.add(previous);
    _redo.clear();
    _revision++;
  }

  /// Pops the most recent undo point, banking [current] for redo, and returns
  /// the document to restore. Callers must guard with [canUndo].
  DesignerDocument undo(DesignerDocument current) {
    final DesignerDocument previous = _undo.removeLast();
    _redo.add(current);
    _revision++;
    return previous;
  }

  /// Pops the most recent redo point, banking [current] for undo, and returns
  /// the document to restore. Callers must guard with [canRedo].
  DesignerDocument redo(DesignerDocument current) {
    final DesignerDocument next = _redo.removeLast();
    _undo.add(current);
    _revision++;
    return next;
  }

  /// Clears all history (used when a fresh template is opened).
  void clear() {
    _undo.clear();
    _redo.clear();
    _revision++;
  }
}
