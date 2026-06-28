// Selection commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlSelection on JetReportDesignerController {
  /// Selects exactly [id] (replacing any prior selection).
  void select(String id) => _setSelection(Selection.of(<String>[id]));

  /// Selects the band with stable id [bandId] (replacing any prior selection).
  /// Exclusive with element/group/scope/report selection. An unknown id is
  /// ignored.
  void selectBand(String bandId) {
    if (findBand(_document.definition, bandId) == null) return;
    _setSelection(Selection.band(bandId));
  }

  /// Selects the group with stable id [groupId]. An unknown id is ignored.
  void selectGroup(String groupId) {
    if (findGroup(_document.definition, groupId) == null) return;
    _setSelection(Selection.group(groupId));
  }

  /// Selects the scope with stable id [scopeId]. An unknown id is ignored.
  void selectScope(String scopeId) {
    if (findScope(_document.definition, scopeId) == null) return;
    _setSelection(Selection.scope(scopeId));
  }

  /// Selects the report/page itself (replacing any prior selection).
  void selectReport() => _setSelection(Selection.report());

  /// Clears the selection.
  void clearSelection() => _setSelection(Selection.empty);

  /// Asks the designer chrome to bring the Properties inspector forward and
  /// move keyboard focus into the selected element's most relevant field (the
  /// canvas calls this on a double-tap). The inspector consumes the request
  /// via [takePropertiesFocus].
  void requestPropertiesFocus() {
    _pendingPropertiesFocus = true;
    _notify();
  }

  /// Consumes a pending Properties-focus request: returns whether one was
  /// pending and clears it. Called once per request by the Properties
  /// inspector after it moves keyboard focus. Does not notify.
  bool takePropertiesFocus() {
    final bool pending = _pendingPropertiesFocus;
    _pendingPropertiesFocus = false;
    return pending;
  }

  // --- Creation --------------------------------------------------------------
  /// Selects every element in the definition.
  void selectAll() => _setSelection(Selection.of(<String>[
        for (final Band band in allBands(_document.definition))
          for (final ReportElement e in band.elements) e.id,
      ]));

  /// Replaces the selection with exactly [ids] (used by marquee select).
  void selectElements(Iterable<String> ids) => _setSelection(Selection.of(ids));

  /// Adds [id] to the selection (shift-click extend).
  void addToSelection(String id) =>
      _setSelection(_document.selection.including(id));

  /// Toggles [id] in/out of the selection (shift-click).
  void toggleSelection(String id) =>
      _setSelection(_document.selection.toggled(id));

  // --- Bulk operations -------------------------------------------------------
}
