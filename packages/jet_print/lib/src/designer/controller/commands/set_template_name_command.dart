/// The command that sets the report template's name (017 / US2 / FR-008).
library;

import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [ReportTemplate.name] to [newName] via `copyWith`, preserving every
/// other field. Renaming to the current name returns the document unchanged, so
/// the controller's `_commit` identity guard records no history entry (a no-op).
///
/// The name is stored verbatim — an empty or whitespace-only name is kept as-is;
/// rendering the localized placeholder for an empty name is a UI concern
/// (FR-010), not a model constraint, which keeps serialization lossless.
class SetTemplateNameCommand extends EditCommand {
  /// Creates a rename to [newName].
  const SetTemplateNameCommand(this.newName);

  /// The new report name.
  final String newName;

  @override
  String get label => 'Rename';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (newName == before.template.name) return before;
    return before.withTemplate(before.template.copyWith(name: newName));
  }
}
