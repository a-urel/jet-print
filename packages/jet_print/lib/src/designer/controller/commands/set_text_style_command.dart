/// The command that restyles a text element (021 / US1 / FR-001…FR-005).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/text_style.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [TextElement] [id]'s whole style with [style] in one undoable
/// step, preserving its text, bounds, binding, and format.
///
/// **No-op** when the element already carries an equal style: returns `before`
/// unchanged, so the controller's `_commit` identity guard records no history
/// and notifies no listener (FR-013 — committing an unchanged value must not
/// pollute the undo stack). Also a no-op for a non-text or absent [id].
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
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id && e is TextElement && e.style != style))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is TextElement)
                  e.copyWith(style: style)
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
