/// Commands that bind report elements to data (US2 / FR-009, FR-012, FR-013).
///
/// Bindings live in the element model: a [TextElement]'s [TextElement.expression]
/// (a `$F{}`/`$P{}`/`$V{}` string; null = static) and an [ImageElement]'s
/// [FieldImageSource]. Each command rebuilds only the touched element (via
/// [updateElement]); an unchanged binding yields a value-equal definition the
/// controller treats as a no-op (no history entry).
library;

import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/text_element.dart';
import '../element_edit_command.dart';

/// Sets (or, when [expression] is null, clears) the data-binding [expression] of
/// the [TextElement] with [id]. A no-op for a non-text or absent id, or when the
/// expression is already equal.
class SetTextBindingCommand extends ElementEditCommand<TextElement> {
  /// Binds [id] to [expression] (null clears the binding).
  const SetTextBindingCommand({required String id, required this.expression})
      : super(id);

  /// The new binding expression, or null to clear it (revert to static text).
  final String? expression;

  @override
  String get label => expression == null ? 'Clear binding' : 'Bind text';

  @override
  TextElement edit(TextElement element) =>
      element.copyWith(expression: () => expression);
}

/// Binds the [ImageElement] with [id] to read its picture from the data [field]
/// (a [FieldImageSource]). A no-op for a non-image or absent id, or when it is
/// already bound to the same field.
class SetImageBindingCommand extends ElementEditCommand<ImageElement> {
  /// Binds image [id] to [field].
  const SetImageBindingCommand({required String id, required this.field})
      : super(id);

  /// The data field supplying the image.
  final String field;

  @override
  String get label => 'Bind image';

  @override
  ImageElement edit(ImageElement element) =>
      element.copyWith(source: FieldImageSource(field));
}
