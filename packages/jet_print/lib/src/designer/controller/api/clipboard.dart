// Clipboard, delete, reorder, align commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlClipboard on JetReportDesignerController {
  /// Deletes the selected elements as one undoable step (FR-014). No-op when the
  /// selection holds no elements (e.g. a band/group/scope or the report).
  void delete() {
    if (_document.selection.ids.isEmpty) return;
    _commit(DeleteCommand(_document.selection.ids.toSet()));
  }

  /// Brings the selection one step toward the front (FR-013).
  void bringForward() => _reorder(ReorderMode.forward);

  /// Sends the selection one step toward the back.
  void sendBackward() => _reorder(ReorderMode.backward);

  /// Brings the selection to the very front.
  void bringToFront() => _reorder(ReorderMode.toFront);

  /// Sends the selection to the very back.
  void sendToBack() => _reorder(ReorderMode.toBack);

  /// Copies the selection to the in-memory clipboard (FR-015).
  ///
  /// A Copy changes derived UI-enablement state ([canPaste] flips `false→true`)
  /// but is **not** a history entry (FR-009) — so it [notifyListeners] to rebuild
  /// the clipboard controls WITHOUT routing through [_commit]. No-op (no notify)
  /// when the selection holds no elements.
  void copy() {
    final List<ClipboardEntry> entries = _collectSelected();
    if (entries.isEmpty) return;
    _clipboard.set(entries);
    _notify();
  }

  /// Cuts: copies the selection, then deletes it (one undoable step).
  void cut() {
    copy();
    delete();
  }

  /// Pastes the clipboard's contents as fresh-id, offset copies, selecting them.
  void paste() {
    if (_clipboard.isEmpty) return;
    final List<ClipboardEntry> copies =
        _buildCopies(_clipboard.entries, targetBandId: _pasteTargetBand());
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// Duplicates the current selection in place (fresh ids + offset), selecting
  /// the copies — without touching the clipboard.
  void duplicate() {
    final List<ClipboardEntry> copies = _buildCopies(_collectSelected());
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// Aligns the (multi-)selection per [kind], one undoable step (FR-012).
  void align(AlignKind kind) =>
      _commitBounds(computeAlign(_collectPositioned(), kind));

  /// Distributes the (multi-)selection evenly along [axis] (FR-012).
  void distribute(DistributeAxis axis) =>
      _commitBounds(computeDistribute(_collectPositioned(), axis));
}
