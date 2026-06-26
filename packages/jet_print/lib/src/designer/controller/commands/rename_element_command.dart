/// The command that sets a report element's display name.
library;

import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the display [name] of the element with [id] (via `withName`; `null`
/// clears it back to the fallback label). Preserves every other field.
/// Renaming to the current name yields a value-equal document, so the
/// controller's commit records no history entry (a no-op). A no-op for an
/// absent id (the transform returns the element unchanged for non-matches).
class RenameElementCommand extends EditCommand {
  /// Creates a rename of element [id] to [name] (`null` clears).
  const RenameElementCommand({required this.id, required this.name});

  /// The target element id.
  final String id;

  /// The new display name, or `null` to clear.
  final String? name;

  @override
  String get label => 'Rename';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition, id, (ReportElement e) => e.withName(name)),
      );
}
