/// The command that sets a text element's display [format] (013) — an ICU
/// number/date pattern applied to the resolved value at render time. Null clears
/// it (unformatted).
library;

import '../../../domain/elements/text_element.dart';
import '../element_edit_command.dart';

/// Sets (or, when [format] is null, clears) the [TextElement] [id]'s display
/// format, preserving text/style/bounds/expression. A no-op for a non-text or
/// absent id, or when the format already matches.
class SetFormatCommand extends ElementEditCommand<TextElement> {
  /// Sets [id]'s format to [format] (null clears it).
  const SetFormatCommand({required String id, required this.format})
      : super(id);

  /// The new format pattern, or null to clear it.
  final String? format;

  @override
  String get label => format == null ? 'Clear format' : 'Set format';

  @override
  TextElement edit(TextElement element) =>
      element.copyWith(format: () => format);
}
