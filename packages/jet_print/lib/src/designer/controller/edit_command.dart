/// The base type for an undoable editing operation.
library;

import 'designer_document.dart';

/// A pure transform from one [DesignerDocument] to the next.
///
/// Every state-changing edit is a command: [apply] takes the document *before*
/// the edit and returns a brand-new document after it, mutating nothing in
/// place. This makes undo/redo correct by construction (the controller keeps the
/// before-snapshot) and makes each operation trivially unit-testable against a
/// fixture. [label] names the operation for diagnostics / potential history UI.
abstract class EditCommand {
  /// Const base constructor for subclasses.
  const EditCommand();

  /// A short, human-readable name for this operation (e.g. `'Move'`).
  String get label;

  /// Returns the document produced by applying this command to [before].
  DesignerDocument apply(DesignerDocument before);
}
