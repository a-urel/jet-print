/// The current designer selection: a set of elements, a single band, or the
/// whole report/page.
library;

/// An immutable selection target.
///
/// A selection is exactly one of: a set of element `id`s (the common case), a
/// single band (by index), or the report/page itself. The three are mutually
/// exclusive — the factories guarantee it — so band/report selections always
/// carry an empty [ids], and element selections carry a null [bandIndex] and a
/// false [isReport].
///
/// Element order is preserved (insertion order) so multi-element operations that
/// need a deterministic anchor — align/distribute — behave predictably.
/// Selection is resolved against the current `ReportTemplate` on demand; it never
/// holds model references, so it stays valid as the immutable model is replaced
/// edit-to-edit.
class Selection {
  const Selection._(this.ids, {this.bandIndex, this.isReport = false});

  /// Builds an element selection from [ids], de-duplicating while preserving
  /// order. Targets no band and not the report.
  factory Selection.of(Iterable<String> ids) {
    final List<String> ordered = <String>[];
    for (final String id in ids) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return Selection._(List<String>.unmodifiable(ordered));
  }

  /// Selects the band at [index] (and nothing else).
  factory Selection.band(int index) =>
      Selection._(const <String>[], bandIndex: index);

  /// Selects the report/page itself (and nothing else).
  factory Selection.report() =>
      const Selection._(<String>[], isReport: true);

  /// The empty selection (nothing selected).
  static const Selection empty = Selection._(<String>[]);

  /// The selected element ids, in stable selection order (unmodifiable). Empty
  /// for a band or report selection.
  final List<String> ids;

  /// The selected band index, or null when a band is not the selection target.
  final int? bandIndex;

  /// Whether the report/page itself is the selection target.
  final bool isReport;

  /// Whether nothing at all is selected (no elements, no band, not the report).
  bool get isEmpty => ids.isEmpty && bandIndex == null && !isReport;

  /// Whether anything is selected.
  bool get isNotEmpty => !isEmpty;

  /// The number of selected elements (0 for a band/report selection).
  int get length => ids.length;

  /// The lone selected element id when exactly one element is selected, else
  /// `null` (used by the Properties panel, which edits a single element).
  String? get singleOrNull => ids.length == 1 ? ids.first : null;

  /// Whether element [id] is selected.
  bool contains(String id) => ids.contains(id);

  /// Returns an element selection with [id] added (switching away from a
  /// band/report target; no-op if already present).
  Selection including(String id) =>
      contains(id) ? this : Selection.of(<String>[...ids, id]);

  /// Returns a selection with [id] removed (no-op if absent).
  Selection excluding(String id) => contains(id)
      ? Selection.of(ids.where((String e) => e != id))
      : this;

  /// Returns a selection with [id] toggled in/out.
  Selection toggled(String id) => contains(id) ? excluding(id) : including(id);

  @override
  bool operator ==(Object other) {
    if (other is! Selection ||
        other.bandIndex != bandIndex ||
        other.isReport != isReport ||
        other.ids.length != ids.length) {
      return false;
    }
    for (int i = 0; i < ids.length; i++) {
      if (other.ids[i] != ids[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(ids), bandIndex, isReport);

  @override
  String toString() {
    if (isReport) return 'Selection(report)';
    if (bandIndex != null) return 'Selection(band $bandIndex)';
    return 'Selection($ids)';
  }
}
