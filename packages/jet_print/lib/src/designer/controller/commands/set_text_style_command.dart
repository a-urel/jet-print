/// The command that restyles a text element (021 / US1 / FR-001…FR-005).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/text_style.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [TextElement] [id]'s whole style with [style] in one undoable
/// step, preserving its text, bounds, binding, and format.
///
/// **No-op** when the element already carries an equal style (value-equal
/// definition → no history, FR-013). Also a no-op for a non-text or absent
/// [id].
class SetTextStyleCommand extends EditCommand {
  /// Creates a restyle of the text element [id] to [style].
  const SetTextStyleCommand({required this.id, required this.style});

  /// The target text element.
  final String id;

  /// The style to apply (whole-value replacement; editors build it with
  /// [JetTextStyle.copyWith] from the current style).
  final JetTextStyle style;

  @override
  String get label => 'Edit text style';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is TextElement ? e.copyWith(style: style) : e,
        ),
      );
}
