/// The command that sets a text element's literal text (FR-019).
library;

import '../../../domain/elements/text_element.dart';
import '../element_edit_command.dart';

/// Sets the [text] of the [TextElement] with [id] (via `copyWith`), preserving
/// its style/bounds/expression. A no-op (value-equal definition → no history)
/// for a non-text or absent id, or when the text already matches.
class SetTextCommand extends ElementEditCommand<TextElement> {
  /// Creates a set-text of [id] to [text].
  const SetTextCommand({required String id, required this.text}) : super(id);

  /// The new literal text.
  final String text;

  @override
  String get label => 'Edit text';

  @override
  TextElement edit(TextElement element) => element.copyWith(text: text);
}
