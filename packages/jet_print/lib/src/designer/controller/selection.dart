/// The set of currently-selected element ids in the designer.
library;

/// An immutable, order-stable set of selected element `id`s.
///
/// Order is preserved (insertion order) so multi-element operations that need a
/// deterministic anchor — align/distribute — behave predictably. Selection is
/// resolved against the current `ReportTemplate` on demand to yield concrete
/// elements; it never holds element references itself, so it stays valid as the
/// immutable model is replaced edit-to-edit.
class Selection {
  const Selection._(this.ids);

  /// Builds a selection from [ids], de-duplicating while preserving order.
  factory Selection.of(Iterable<String> ids) {
    final List<String> ordered = <String>[];
    for (final String id in ids) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return Selection._(List<String>.unmodifiable(ordered));
  }

  /// The empty selection.
  static const Selection empty = Selection._(<String>[]);

  /// The selected ids, in stable selection order (unmodifiable).
  final List<String> ids;

  /// Whether nothing is selected.
  bool get isEmpty => ids.isEmpty;

  /// Whether at least one element is selected.
  bool get isNotEmpty => ids.isNotEmpty;

  /// The number of selected elements.
  int get length => ids.length;

  /// The lone selected id when exactly one element is selected, else `null`
  /// (used by the Properties panel, which edits a single element).
  String? get singleOrNull => ids.length == 1 ? ids.first : null;

  /// Whether [id] is selected.
  bool contains(String id) => ids.contains(id);

  /// Returns a selection with [id] added (no-op if already present).
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
    if (other is! Selection || other.ids.length != ids.length) return false;
    for (int i = 0; i < ids.length; i++) {
      if (other.ids[i] != ids[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);

  @override
  String toString() => 'Selection($ids)';
}
