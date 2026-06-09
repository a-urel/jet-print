/// The payload dragged from the Data Source panel onto the canvas (US2 / FR-011).
library;

/// Identifies the data field being dragged so the canvas can create (or target)
/// an element bound to it. Only **leaf** (scalar) fields are draggable; a
/// collection (branch) node is not, so dropping one is a no-op by construction.
class FieldDragData {
  /// Wraps a drag of the field named [fieldName].
  const FieldDragData({required this.fieldName});

  /// The leaf field's name, turned into a `$F{fieldName}` binding on drop.
  final String fieldName;
}
