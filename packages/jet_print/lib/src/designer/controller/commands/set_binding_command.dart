/// Commands that bind report elements to data (US2 / FR-009, FR-012, FR-013).
///
/// Bindings live in the element model: a [TextElement]'s [TextElement.expression]
/// (a `$F{}`/`$P{}`/`$V{}` string; null = static) and an [ImageElement]'s
/// [FieldImageSource]. Each command rebuilds only the touched element, preserving
/// every other element referentially (FR-025), and is a no-op (returns `before`
/// unchanged, so no history entry) when the binding already matches.
library;

import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets (or, when [expression] is null, clears) the data-binding [expression] of
/// the [TextElement] with [id]. A no-op for a non-text or absent id, or when the
/// expression is already equal.
class SetTextBindingCommand extends EditCommand {
  /// Binds [id] to [expression] (null clears the binding).
  const SetTextBindingCommand({required this.id, required this.expression});

  /// The target text element.
  final String id;

  /// The new binding expression, or null to clear it (revert to static text).
  final String? expression;

  @override
  String get label => expression == null ? 'Clear binding' : 'Bind text';

  @override
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id && e is TextElement && e.expression != expression))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is TextElement)
                  TextElement(
                    id: e.id,
                    bounds: e.bounds,
                    text: e.text,
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

/// Binds the [ImageElement] with [id] to read its picture from the data [field]
/// (a [FieldImageSource]). A no-op for a non-image or absent id, or when it is
/// already bound to the same field.
class SetImageBindingCommand extends EditCommand {
  /// Binds image [id] to [field].
  const SetImageBindingCommand({required this.id, required this.field});

  /// The target image element.
  final String id;

  /// The data field supplying the image.
  final String field;

  @override
  String get label => 'Bind image';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final FieldImageSource source = FieldImageSource(field);
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) =>
            e.id == id && e is ImageElement && e.source != source))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is ImageElement)
                  ImageElement(
                    id: e.id,
                    bounds: e.bounds,
                    source: source,
                    fit: e.fit,
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
