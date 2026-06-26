/// The command that sets a text element's display [format] (013) — an ICU
/// number/date pattern applied to the resolved value at render time. Null clears
/// it (unformatted).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets (or, when [format] is null, clears) the [TextElement] [id]'s display
/// format, preserving text/style/bounds/expression. A no-op for a non-text or
/// absent id, or when the format already matches.
class SetFormatCommand extends EditCommand {
  /// Sets [id]'s format to [format] (null clears it).
  const SetFormatCommand({required this.id, required this.format});

  /// The target text element.
  final String id;

  /// The new format pattern, or null to clear it.
  final String? format;

  @override
  String get label => format == null ? 'Clear format' : 'Set format';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is TextElement
              ? TextElement(
                  id: e.id,
                  bounds: e.bounds,
                  text: e.text,
                  style: e.style,
                  expression: e.expression,
                  format: format,
                  name: e.name,
                )
              : e,
        ),
      );
}
