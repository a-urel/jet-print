/// Horizontal bands — the vertical structure of a banded report.
library;

/// The role a band plays in the report's vertical flow. The renderer
/// decides repetition/placement per type; here it is pure structure.
enum BandType {
  /// Printed once at the very start of the report.
  title,

  /// Repeated at the top of every page.
  pageHeader,

  /// **Reserved**: meant to repeat above the detail section on each
  /// page/column, but not laid out yet; `validate` rejects a band in its slot.
  columnHeader,

  /// Printed when a group's key changes (before its details).
  groupHeader,

  /// Repeated once per data row.
  detail,

  /// Printed when a group ends (after its details).
  groupFooter,

  /// **Reserved**: meant to repeat below the detail section on each
  /// page/column, but not laid out yet; `validate` rejects a band in its slot.
  columnFooter,

  /// Repeated at the bottom of every page.
  pageFooter,

  /// Printed once at the very end of the report.
  summary,

  /// **Reserved**: meant to draw behind every page (frames), but not laid out
  /// yet; `validate` rejects a band in its slot. For a watermark use
  /// `PageFurniture.watermark`.
  background,

  /// Printed instead of details when the data set is empty.
  noData,
}
