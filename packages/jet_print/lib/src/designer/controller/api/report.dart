// Report-level (page / watermark / name) commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlReport on JetReportDesignerController {
  /// Sets the report's page [format] — size and/or margins — as one undoable,
  /// notifying step (018 / FR-006/FR-007).
  ///
  /// The Properties panel composes the next [PageFormat] from the live one
  /// (apply a paper preset, swap width/height for orientation, set one margin
  /// side via `copyWith`) and hands the whole value over; this method
  /// [clampPageFormat]s it first so every produced page keeps a positive content
  /// area (FR-009), then commits it. Routed through `_commit`, so a page equal
  /// to the current one records no history and notifies no listener (FR-007),
  /// undo restores the exact prior page, and elements are never repositioned
  /// (FR-013). Canvas, preview, and export all read `definition.page`, so the one
  /// notification propagates the change everywhere (WYSIWYG).
  void setPageFormat(PageFormat format) {
    _commit(SetPageFormatCommand(clampPageFormat(format)));
  }

  /// Sets (or clears, with null) the report's page watermark as one undoable
  /// step. Routed through `_commit`, so setting the current watermark records no
  /// history; canvas/preview/export all read `definition.furniture.watermark`,
  /// so the one notification propagates everywhere (WYSIWYG).
  void setWatermark(Watermark? watermark) =>
      _commit(SetWatermarkCommand(watermark));

  // --- Numeric geometry + text (Properties / inline) -------------------------
  /// Renames the report to [name] as a single undoable step (017 / FR-008).
  ///
  /// The name is stored verbatim: an empty or whitespace-only name is kept as
  /// `''`, and the UI shows the localized placeholder for an empty name
  /// (FR-010). Renaming to the current name is a no-op — it records no history
  /// entry and notifies no listeners. The new name appears on [definition],
  /// which is the value a host persists on save.
  void rename(String name) => _commit(SetDefinitionNameCommand(name));
}
