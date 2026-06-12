/// The command that changes the report's page format (size and/or margins).
library;

import '../../../domain/page_format.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the report's [PageFormat] to [format] (already clamped by the
/// controller).
///
/// A page edit — paper size, orientation swap, or a single margin side — is one
/// change to one immutable [PageFormat], so this is a single-field template
/// transform. [apply] returns the document unchanged when the page already
/// equals [format] (no-op), else swaps in `template.copyWith(page:)`. It does
/// **not** clamp (the controller clamps the input) and does **not** touch
/// bands/elements — `copyWith(page:)` leaves content where it is, so element
/// top-left anchors are preserved across a resize (FR-013). The selection is
/// left as-is, so undo restores the exact prior page and selection.
class SetPageFormatCommand extends EditCommand {
  /// Creates a page-format change to [format].
  const SetPageFormatCommand(this.format);

  /// The new (already-clamped) page format.
  final PageFormat format;

  @override
  String get label => 'Change page';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (before.template.page == format) return before;
    return before.withTemplate(before.template.copyWith(page: format));
  }
}
