/// Catalog metadata for one open-source font family — cheap to enumerate
/// without loading any font bytes.
library;

import 'package:jet_print/jet_print.dart' show JetFontWeight;

/// The (weight, italic) slot a face fills within a family.
typedef FontFaceSlot = ({JetFontWeight weight, bool italic});

/// One family in the bundled catalog: its display [name] (also the name stored
/// in reports), its [license] identifier, and the asset key of each present
/// face keyed by its [FontFaceSlot]. Asset keys are package-prefixed
/// (`packages/jet_print_google_fonts/...`) so they resolve for consumers and in
/// this package's own tests.
class GoogleFontEntry {
  /// Creates a catalog entry.
  const GoogleFontEntry({
    required this.name,
    required this.license,
    required this.faceAssets,
  });

  /// The display + report-stored family name (e.g. `"Noto Sans"`).
  final String name;

  /// The license identifier (`'OFL-1.1'` or `'Apache-2.0'`).
  final String license;

  /// Asset key per present face. Always contains the regular slot
  /// `(weight: JetFontWeight.normal, italic: false)`.
  final Map<FontFaceSlot, String> faceAssets;
}
