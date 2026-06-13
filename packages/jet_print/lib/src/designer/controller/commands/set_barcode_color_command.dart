/// The command that recolors a barcode element (021 / US3 / FR-011).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/color.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [BarcodeElement] [id]'s foreground [color] in one undoable
/// step, preserving its symbology, data, and bounds.
///
/// **No-op** when the element already carries an equal color: returns `before`
/// unchanged, so the controller's `_commit` identity guard records no history
/// and notifies no listener (FR-013). Also a no-op for a non-barcode or
/// absent [id].
class SetBarcodeColorCommand extends EditCommand {
  /// Creates a recolor of the barcode element [id] to [color].
  const SetBarcodeColorCommand({required this.id, required this.color});

  /// The target barcode element.
  final String id;

  /// The foreground (bar) color to apply.
  final JetColor color;

  @override
  String get label => 'Edit barcode color';

  @override
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id && e is BarcodeElement && e.color != color))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is BarcodeElement)
                  e.copyWith(color: color)
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
