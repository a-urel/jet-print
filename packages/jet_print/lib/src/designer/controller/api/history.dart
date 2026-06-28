// Undo / redo commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlHistory on JetReportDesignerController {
  /// Reverts the last edit, restoring model and selection (no-op if [canUndo]
  /// is false).
  void undo() {
    if (!_history.canUndo) return;
    _document = _history.undo(_document);
    _notify();
  }

  /// Re-applies the last undone edit (no-op if [canRedo] is false).
  void redo() {
    if (!_history.canRedo) return;
    _document = _history.redo(_document);
    _notify();
  }
}
