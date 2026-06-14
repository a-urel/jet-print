/// The command that sets a text element's literal text (FR-019).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [text] of the [TextElement] with [id] (via `copyWith`), preserving
/// its style/bounds/expression. A no-op (value-equal definition → no history)
/// for a non-text or absent id, or when the text already matches.
class SetTextCommand extends EditCommand {
  /// Creates a set-text of [id] to [text].
  const SetTextCommand({required this.id, required this.text});

  /// The target text element.
  final String id;

  /// The new literal text.
  final String text;

  @override
  String get label => 'Edit text';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) => e is TextElement ? e.copyWith(text: text) : e),
      );
}
