/// The command that sets a report element's display name.
library;

import '../../../domain/report_element.dart';
import '../element_edit_command.dart';

/// Sets the display [name] of the element with [id] (via `withName`; `null`
/// clears it back to the fallback label). Preserves every other field.
/// Renaming to the current name yields a value-equal document, so the
/// controller's commit records no history entry (a no-op). A no-op for an
/// absent id (the transform returns the element unchanged for non-matches).
class RenameElementCommand extends ElementEditCommand<ReportElement> {
  /// Creates a rename of element [id] to [name] (`null` clears).
  const RenameElementCommand({required String id, required this.name})
      : super(id);

  /// The new display name, or `null` to clear.
  final String? name;

  @override
  String get label => 'Rename';

  @override
  ReportElement edit(ReportElement element) => element.withName(name);
}
