/// The command behind the unified value field (013): it sets a text element's
/// literal [text] and binding [expression] together, as one undoable step, so
/// switching a label between literal and bound is a single edit (FR-005).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [TextElement] [id]'s [text] and [expression] atomically (preserving
/// style/bounds/format). A no-op for a non-text or absent id, or when both
/// already match.
class SetValueCommand extends EditCommand {
  /// Creates a set-value of [id].
  const SetValueCommand({
    required this.id,
    required this.text,
    required this.expression,
  });

  /// The target text element.
  final String id;

  /// The element's literal text after the edit.
  final String text;

  /// The binding expression after the edit, or null for a literal.
  final String? expression;

  @override
  String get label => expression == null ? 'Edit value' : 'Bind value';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is TextElement
              ? TextElement(
                  id: e.id,
                  bounds: e.bounds,
                  text: text,
                  style: e.style,
                  expression: expression,
                  format: e.format,
                  name: e.name,
                  visible: e.visible,
                )
              : e,
        ),
      );
}
