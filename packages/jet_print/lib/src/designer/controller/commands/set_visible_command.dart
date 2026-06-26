/// Commands that set an object's [visible] BoolProperty (visible property).
library;

import '../../../domain/band.dart';
import '../../../domain/bool_property.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [visible] property of the element with [id]. No-op for an absent id
/// or an already-equal value.
class SetElementVisibleCommand extends EditCommand {
  const SetElementVisibleCommand({required this.id, required this.visible});

  final String id;
  final BoolProperty visible;

  @override
  String get label => 'Set visibility';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition, id, (ReportElement e) => e.withVisible(visible)),
      );
}

/// Sets the [visible] property of the band with [bandId].
class SetBandVisibleCommand extends EditCommand {
  const SetBandVisibleCommand({required this.bandId, required this.visible});

  final String bandId;
  final BoolProperty visible;

  @override
  String get label => 'Set band visibility';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(before.definition, bandId,
            (Band b) => b.copyWith(visible: visible)),
      );
}
