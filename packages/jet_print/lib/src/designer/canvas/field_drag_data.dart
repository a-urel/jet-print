/// The payload dragged from the Data Source panel onto the canvas (US2 / FR-011).
library;

/// Identifies the data field being dragged so the canvas can create (or target)
/// an element bound to it. Scalar fields and collection (branch) fields are both
/// draggable; [isCollection] distinguishes the two cases on drop.
class FieldDragData {
  /// Wraps a drag of the field named [fieldName]. [isCollection] marks a
  /// collection (branch) field, whose drop creates a nested list rather than a
  /// bound text element.
  const FieldDragData({required this.fieldName, this.isCollection = false});

  /// The field's name. A scalar becomes a `$F{fieldName}` binding; a collection
  /// becomes a nested list bound to [fieldName].
  final String fieldName;

  /// Whether the dragged field is a collection (true) or a scalar (false).
  final bool isCollection;
}
