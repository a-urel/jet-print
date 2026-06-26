/// The command that sets a band's display name.
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the display [name] of the band with [bandId] (`null` clears it back to
/// the localized type label). Renaming to the current name is a value-equal
/// no-op; a no-op for an absent id.
///
/// `Band.copyWith(name: null)` cannot clear an existing name (null is treated
/// as "keep current"), so this command always reconstructs the [Band] fully,
/// passing [name] verbatim — including `null`.
class RenameBandCommand extends EditCommand {
  /// Creates a rename of band [bandId] to [name] (`null` clears).
  const RenameBandCommand({required this.bandId, required this.name});

  /// The target band id.
  final String bandId;

  /// The new display name, or `null` to clear.
  final String? name;

  @override
  String get label => 'Rename';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(
          before.definition,
          bandId,
          (Band b) => Band(
            id: b.id,
            type: b.type,
            height: b.height,
            elements: b.elements,
            columnLayout: b.columnLayout,
            name: name,
          ),
        ),
      );
}
