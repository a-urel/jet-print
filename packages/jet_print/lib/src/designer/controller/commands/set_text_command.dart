/// The command that sets a text element's literal text (FR-019).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [text] of the [TextElement] with [id] (via `copyWith`), preserving
/// its style/bounds/expression. A no-op for non-text or absent ids.
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
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id && e is TextElement && e.text != text))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is TextElement) e.copyWith(text: text) else e,
            ]);
          }()
        else
          band,
    ];
    if (!changed) return before;
    return before.withTemplate(before.template.copyWith(bands: bands));
  }
}
