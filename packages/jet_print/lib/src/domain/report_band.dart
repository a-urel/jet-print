/// Horizontal bands — the vertical structure of a banded report.
library;

/// The role a band plays in the report's vertical flow. The renderer (spec 008)
/// decides repetition/placement per type; here it is pure structure.
enum BandType {
  /// Printed once at the very start of the report.
  title,

  /// Repeated at the top of every page.
  pageHeader,

  /// Repeated above the detail section on each page/column.
  columnHeader,

  /// Printed when a group's key changes (before its details).
  groupHeader,

  /// Repeated once per data row.
  detail,

  /// Printed when a group ends (after its details).
  groupFooter,

  /// Repeated below the detail section on each page/column.
  columnFooter,

  /// Repeated at the bottom of every page.
  pageFooter,

  /// Printed once at the very end of the report.
  summary,

  /// Drawn behind every page (watermarks, frames).
  background,

  /// Printed instead of details when the data set is empty.
  noData,
}
