/// The Fill output IR (spec 007b): an ordered stream of resolved band instances,
/// each carrying a frozen variable snapshot. Pure data with value equality, so a
/// fill is a snapshot-testable data golden. INTERNAL and intentionally incomplete
/// — 007c extends the stream with group bands.
library;

import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../expression/value.dart';

/// One resolved band instance: its [type], designed [height], resolved
/// [elements] (copies), and the [variables] snapshot as of when it was emitted.
class FilledBand {
  /// Creates a filled band, defensively freezing [elements] and [variables] so
  /// the snapshot is genuinely immutable (callers cannot mutate it after fill).
  FilledBand({
    required this.type,
    required this.height,
    required List<ReportElement> elements,
    required Map<String, JetValue> variables,
  })  : elements = List<ReportElement>.unmodifiable(elements),
        variables = Map<String, JetValue>.unmodifiable(variables);

  /// The band's role (title/groupHeader/detail/groupFooter/summary/noData).
  final BandType type;

  /// The band's designed height, in points.
  final double height;

  /// The resolved element copies (unmodifiable).
  final List<ReportElement> elements;

  /// The calculator's frozen variable values at this instance (unmodifiable).
  final Map<String, JetValue> variables;

  @override
  bool operator ==(Object other) =>
      other is FilledBand &&
      other.type == type &&
      other.height == height &&
      _listEquals(other.elements, elements) &&
      _mapEquals(other.variables, variables);

  @override
  int get hashCode {
    // Order-independent over the variables map, to match the order-insensitive
    // _mapEquals — equal bands must hash equally regardless of insertion order.
    // Object.hashAllUnordered combines per-entry hashes commutatively without the
    // XOR-cancellation footgun (two equal per-entry hashes would cancel to zero).
    final int varsHash = Object.hashAllUnordered(
      <int>[
        for (final MapEntry<String, JetValue> e in variables.entries)
          Object.hash(e.key, e.value),
      ],
    );
    return Object.hash(type, height, Object.hashAll(elements), varsHash);
  }

  @override
  String toString() => 'FilledBand(${type.name}, ${elements.length} elements)';
}

/// The full resolved report: a [page] and an ordered list of [bands].
class FilledReport {
  /// Creates a filled report.
  FilledReport({required this.page, required List<FilledBand> bands})
      : bands = List<FilledBand>.unmodifiable(bands);

  /// The page the report lays out onto.
  final PageFormat page;

  /// The ordered resolved band instances.
  final List<FilledBand> bands;

  @override
  bool operator ==(Object other) =>
      other is FilledReport &&
      other.page == page &&
      _listEquals(other.bands, bands);

  @override
  int get hashCode => Object.hash(page, Object.hashAll(bands));

  @override
  String toString() => 'FilledReport(${bands.length} bands)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, JetValue> a, Map<String, JetValue> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<String, JetValue> e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
