/// The command that inserts a newly-created element into a band (FR-001/002/004).
library;

import '../../../domain/band.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/box_style.dart';
import '../../../domain/styles/color.dart';
import '../../canvas/design_tunables.dart';
import '../band_walker.dart';
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
        symbology: BarcodeSymbology.auto,
        data: '1234567890',
      );
  }
}

/// Inserts a fully-formed [element] into the band with stable id [bandId]
/// (appended, so it lands on top in z-order), clamped to the band, and selects
/// it. A no-op for an unknown [bandId].
///
/// The concrete element (with its assigned id and default size) is baked into
/// the command by the controller, so redo re-inserts the *exact* same element —
/// ids never drift across undo/redo.
class CreateElementCommand extends EditCommand {
  /// Creates an insert command for [element] into band [bandId].
  const CreateElementCommand({required this.bandId, required this.element});

  /// The stable id of the target band.
  final String bandId;

  /// The element to insert (id and size already assigned).
  final ReportElement element;

  @override
  String get label => 'Create ${element.typeKey}';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final Band? band = findBand(before.definition, bandId);
    if (band == null) return before;
    final ReportElement placed = element
        .withBounds(clampToBand(element.bounds, band, before.definition.page));
    return before.withDefinition(
      updateBand(
        before.definition,
        bandId,
        (Band b) =>
            b.copyWith(elements: <ReportElement>[...b.elements, placed]),
      ),
      selection: Selection.of(<String>[placed.id]),
    );
  }
}
