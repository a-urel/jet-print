/// Assigns collision-free element ids within a definition (FR-004).
library;

import '../../domain/report_definition.dart';
import 'band_walker.dart';

/// Generates unique element ids of the form `<typeKey><n>` (e.g. `text7`).
///
/// A single monotonic counter is shared across types, so ids never collide
/// regardless of type. On [seedFrom] the counter jumps past the largest numeric
/// suffix found among existing ids, guaranteeing that ids minted after opening a
/// definition (create / paste / duplicate) cannot clash with ones already
/// present.
class ElementIdFactory {
  int _counter = 0;

  static final RegExp _trailingDigits = RegExp(r'(\d+)$');

  /// Resets the counter to one past the largest numeric id suffix among **all**
  /// ids in [definition] — element, band, scope, and group ids (or 0 when none
  /// carries a numeric suffix). Scanning every id (not just element ids) keeps
  /// minted band/group/scope ids collision-free too (FR-004).
  void seedFrom(ReportDefinition definition) {
    int max = 0;
    for (final String id in allIds(definition)) {
      final Match? match = _trailingDigits.firstMatch(id);
      if (match != null) {
        final int value = int.parse(match.group(1)!);
        if (value > max) max = value;
      }
    }
    _counter = max;
  }

  /// Returns the next unique id for an element whose type key is [typeKey].
  String next(String typeKey) => '$typeKey${++_counter}';
}
