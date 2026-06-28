/// The command that sets (or clears) the report's page watermark.
library;

import '../../../domain/report_definition.dart';
import '../../../domain/watermark.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets `furniture.watermark` to [watermark] (null clears it).
///
/// [PageFurniture.copyWith] is set-only and cannot null a slot, so [apply]
/// constructs a fresh [PageFurniture] with every existing slot copied and
/// `watermark` set explicitly — the only way to support clearing. Returns the
/// document unchanged when the watermark already equals [watermark] (no-op);
/// the selection is untouched, so undo restores the exact prior watermark.
class SetWatermarkCommand extends EditCommand {
  /// Creates a watermark change to [watermark] (null clears).
  const SetWatermarkCommand(this.watermark);

  /// The new watermark, or null to remove it.
  final Watermark? watermark;

  @override
  String get label => 'Set watermark';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final PageFurniture f = before.definition.furniture;
    if (f.watermark == watermark) return before;
    final PageFurniture next = PageFurniture(
      pageHeader: f.pageHeader,
      pageFooter: f.pageFooter,
      columnHeader: f.columnHeader,
      columnFooter: f.columnFooter,
      background: f.background,
      watermark: watermark,
    );
    return before.withDefinition(before.definition.copyWith(furniture: next));
  }
}
