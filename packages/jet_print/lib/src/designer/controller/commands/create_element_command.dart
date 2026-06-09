/// The command that inserts a newly-created element into a band (FR-001/002/004).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../../../domain/report_template.dart';
import '../../../domain/styles/box_style.dart';
import '../../../domain/styles/color.dart';
import '../../canvas/design_tunables.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../element_bounds.dart';
import '../selection.dart';

/// Builds a default element of [type] with the given [id] and [bounds].
///
/// The id and size are decided by the controller (the id factory + the
/// per-type defaults in [kDefaultElementSize]); this factory fills in the
/// remaining type-specific attributes a brand-new element needs to render.
ReportElement buildDefaultElement(
  DesignerToolType type,
  String id,
  JetRect bounds,
) {
  switch (type) {
    case DesignerToolType.text:
      return TextElement(id: id, bounds: bounds, text: 'Text');
    case DesignerToolType.shape:
      return ShapeElement(
        id: id,
        bounds: bounds,
        kind: ShapeKind.rectangle,
        style: const JetBoxStyle(stroke: JetColor.black),
      );
    case DesignerToolType.image:
      // An unbound image: the design-time renderer shows a placeholder until a
      // source is configured (out of scope this iteration).
      return ImageElement(
          id: id, bounds: bounds, source: const FieldImageSource(''));
    case DesignerToolType.barcode:
      return BarcodeElement(
        id: id,
        bounds: bounds,
        symbology: BarcodeSymbology.qrCode,
        data: '1234567890',
      );
  }
}

/// Inserts a fully-formed [element] into the band at [bandIndex] (appended, so
/// it lands on top in z-order), clamped to the band, and selects it.
///
/// The concrete element (with its assigned id and default size) is baked into
/// the command by the controller, so redo re-inserts the *exact* same element —
/// ids never drift across undo/redo.
class CreateElementCommand extends EditCommand {
  /// Creates an insert command for [element] into band [bandIndex].
  const CreateElementCommand({required this.bandIndex, required this.element});

  /// The index of the target band within `template.bands`.
  final int bandIndex;

  /// The element to insert (id and size already assigned).
  final ReportElement element;

  @override
  String get label => 'Create ${element.typeKey}';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final ReportTemplate template = before.template;
    final ReportBand band = template.bands[bandIndex];
    final ReportElement placed =
        element.withBounds(clampToBand(element.bounds, band, template.page));
    final ReportBand updated = band.copyWith(
      elements: <ReportElement>[...band.elements, placed],
    );
    final List<ReportBand> bands = <ReportBand>[...template.bands];
    bands[bandIndex] = updated;
    return DesignerDocument(
      template: template.copyWith(bands: bands),
      selection: Selection.of(<String>[placed.id]),
    );
  }
}
