/// Pure measurement helpers shared by the rulers.
///
/// A **display-only** projection of the model's point-based geometry into
/// millimetres (FR-005): the report model is untouched — these convert numbers
/// for the rulers' labels and extent highlight only. Pure Dart (plus the domain
/// geometry value types); no Flutter, no rendering, no serialization — so the
/// projection is unit-testable and carries no view coupling.
library;

/// Points per millimetre: `72 / 25.4` (72 dpi over 25.4 mm-per-inch). The single
/// conversion constant the rulers calibrate against.
const double kPointsPerMm = 72 / 25.4;

/// Converts a length in PDF points to millimetres (display-only, FR-005).
double pointsToMm(double points) => points / kPointsPerMm;

/// Converts a length in millimetres to PDF points.
double mmToPoints(double mm) => mm * kPointsPerMm;
