/// The current designer selection: a set of elements, a single band, a single
/// group, a single scope, or the whole report/page.
library;

/// An immutable selection target.
///
/// A selection is exactly one of: a set of element `id`s (the common case), a
/// single band (by stable [bandId]), a single group (by [groupId]), a single
/// scope (by [scopeId]), or the report/page itself. They are mutually
/// exclusive — the factories guarantee it — so a band/group/scope/report
/// selection always carries an empty [ids], and an element selection carries
/// null ids for the others and a false [isReport].
///
/// Reification (spec 024): a band, group, and scope are now addressed by their
/// **stable id**, not a flat list index — so a selection stays valid across
/// add/remove/reorder, and resolves against the current [ReportDefinition] on
/// demand. It never holds model references, so it survives edit-to-edit
/// replacement of the immutable model.
///
/// Element order is preserved (insertion order) so multi-element operations that
/// need a deterministic anchor — align/distribute — behave predictably.
class Selection {
  const Selection._(
    this.ids, {
    this.bandId,
    this.groupId,
    this.scopeId,
    this.isReport = false,
  });

  /// Builds an element selection from [ids], de-duplicating while preserving
  /// order. Targets no band/group/scope and not the report.
  factory Selection.of(Iterable<String> ids) {
    final List<String> ordered = <String>[];
    for (final String id in ids) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return Selection._(List<String>.unmodifiable(ordered));
  }

  /// Selects the band with stable id [bandId] (and nothing else).
  factory Selection.band(String bandId) =>
      Selection._(const <String>[], bandId: bandId);

  /// Selects the group with stable id [groupId] (and nothing else).
  factory Selection.group(String groupId) =>
      Selection._(const <String>[], groupId: groupId);

  /// Selects the scope with stable id [scopeId] (and nothing else).
  factory Selection.scope(String scopeId) =>
      Selection._(const <String>[], scopeId: scopeId);

  /// Selects the report/page itself (and nothing else).
  factory Selection.report() => const Selection._(<String>[], isReport: true);

  /// The empty selection (nothing selected).
  static const Selection empty = Selection._(<String>[]);

  /// The selected element ids, in stable selection order (unmodifiable). Empty
  /// for a band/group/scope/report selection.
  final List<String> ids;

  /// The selected band's stable id, or null when a band is not the target.
  final String? bandId;

  /// The selected group's stable id, or null when a group is not the target.
  final String? groupId;

  /// The selected scope's stable id, or null when a scope is not the target.
  final String? scopeId;

  /// Whether the report/page itself is the selection target.
  final bool isReport;

  /// Whether nothing at all is selected.
  bool get isEmpty =>
      ids.isEmpty &&
      bandId == null &&
      groupId == null &&
      scopeId == null &&
      !isReport;

  /// Whether anything is selected.
  bool get isNotEmpty => !isEmpty;

  /// The number of selected elements (0 for a band/group/scope/report target).
  int get length => ids.length;

  /// The lone selected element id when exactly one element is selected, else
  /// `null` (used by the Properties panel, which edits a single element).
  String? get singleOrNull => ids.length == 1 ? ids.first : null;

  /// Whether element [id] is selected.
  bool contains(String id) => ids.contains(id);

  /// Returns an element selection with [id] added (switching away from a
  /// band/group/scope/report target; no-op if already present).
  Selection including(String id) =>
      contains(id) ? this : Selection.of(<String>[...ids, id]);

  /// Returns a selection with [id] removed (no-op if absent).
  Selection excluding(String id) =>
      contains(id) ? Selection.of(ids.where((String e) => e != id)) : this;

  /// Returns a selection with [id] toggled in/out.
  Selection toggled(String id) => contains(id) ? excluding(id) : including(id);

  @override
  bool operator ==(Object other) {
    if (other is! Selection ||
        other.bandId != bandId ||
        other.groupId != groupId ||
        other.scopeId != scopeId ||
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
  int get hashCode =>
      Object.hash(Object.hashAll(ids), bandId, groupId, scopeId, isReport);

  @override
  String toString() {
    if (isReport) return 'Selection(report)';
    if (bandId != null) return 'Selection(band $bandId)';
    if (groupId != null) return 'Selection(group $groupId)';
    if (scopeId != null) return 'Selection(scope $scopeId)';
    return 'Selection($ids)';
  }
}
