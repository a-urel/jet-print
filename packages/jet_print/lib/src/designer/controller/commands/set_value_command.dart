/// The command behind the unified value field (013): it sets a text element's
/// literal [text] and binding [expression] together, as one undoable step, so
/// switching a label between literal and bound is a single edit (FR-005).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
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
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id &&
            e is TextElement &&
            (e.text != text || e.expression != expression)))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is TextElement)
                  TextElement(
                    id: e.id,
                    bounds: e.bounds,
                    text: text,
                    style: e.style,
                    expression: expression,
                    format: e.format,
                  )
                else
                  e,
            ]);
          }()
        else
          band,
    ];
    if (!changed) return before;
    return before.withTemplate(before.template.copyWith(bands: bands));
  }
}
