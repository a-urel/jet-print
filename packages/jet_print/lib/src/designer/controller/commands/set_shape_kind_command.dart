/// The command that changes a shape element's form (020 / US1 / FR-004).
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [ShapeElement] [id]'s form to [kind] in one undoable step,
/// preserving its bounds and style.
///
/// * **No-op** when the element is already that form *and* carries no preserved
///   [ShapeElement.unknownForm]: returns `before` unchanged, so the controller's
///   `_commit` identity guard records no history and notifies no listener
///   (FR-005). A shape rendered as a rectangle only because its serialized form
///   was unrecognized is therefore *not* a no-op when rectangle is picked — the
///   pick is a real choice that clears the preserved form.
/// * Switching **away from** [ShapeKind.line] resets the line-only
///   [ShapeElement.flipDiagonal] to false, keeping the option coherent for
///   closed forms (a spec edge case); staying on/returning to a line keeps it.
/// * Any deliberate pick clears [ShapeElement.unknownForm] (FR-009): choosing a
///   known form supersedes a preserved unrecognized one.
///
/// A no-op for a non-shape or absent [id].
class SetShapeKindCommand extends EditCommand {
  /// Creates a pick of [kind] for the shape [id].
  const SetShapeKindCommand({required this.id, required this.kind});

  /// The target shape element.
  final String id;

  /// The form to switch to.
  final ShapeKind kind;

  @override
  String get label => 'Set shape';

  @override
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any(
            (ReportElement e) => e.id == id && e is ShapeElement && _isEdit(e)))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (e.id == id && e is ShapeElement)
                  e.copyWith(
                    kind: kind,
                    flipDiagonal:
                        kind == ShapeKind.line ? e.flipDiagonal : false,
                    clearUnknownForm: true,
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

  /// Whether picking [kind] actually changes [shape] — true unless it is already
  /// that form with no preserved unknown form to clear.
  bool _isEdit(ShapeElement shape) =>
      shape.kind != kind || shape.unknownForm != null;
}
