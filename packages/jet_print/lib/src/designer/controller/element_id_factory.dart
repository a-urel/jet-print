/// Assigns collision-free element ids within a template (FR-004).
library;

import '../../domain/report_template.dart';

/// Generates unique element ids of the form `<typeKey><n>` (e.g. `text7`).
///
/// A single monotonic counter is shared across types, so ids never collide
/// regardless of type. On [seedFrom] the counter jumps past the largest numeric
/// suffix found among existing ids, guaranteeing that ids minted after opening a
/// template (create / paste / duplicate) cannot clash with ones already present.
class ElementIdFactory {
  int _counter = 0;

  static final RegExp _trailingDigits = RegExp(r'(\d+)$');

  /// Resets the counter to one past the largest numeric id suffix in [template]
  /// (or 0 when no element carries a numeric suffix).
  void seedFrom(ReportTemplate template) {
    int max = 0;
    for (final band in template.bands) {
      for (final element in band.elements) {
        final Match? match = _trailingDigits.firstMatch(element.id);
        if (match != null) {
          final int value = int.parse(match.group(1)!);
          if (value > max) max = value;
        }
      }
    }
    _counter = max;
  }

  /// Returns the next unique id for an element whose type key is [typeKey].
  String next(String typeKey) => '$typeKey${++_counter}';
}
