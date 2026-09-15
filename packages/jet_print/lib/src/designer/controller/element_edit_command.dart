/// The shared base for single-element setter commands.
library;

import '../../domain/report_element.dart';
import 'band_walker.dart';
import 'designer_document.dart';
import 'edit_command.dart';

/// An [EditCommand] that rewrites the single element [id] of concrete type [E]
/// through [edit], leaving every other element untouched.
///
/// Funnels through [updateElement], so a non-[E] or absent [id] — or an [edit]
/// that changes nothing — yields a value-equal definition the controller's
/// commit treats as a no-op (no history entry). Subclasses supply only their
/// fields, a [label], and the typed [edit] transform.
abstract class ElementEditCommand<E extends ReportElement> extends EditCommand {
  /// Const base constructor targeting the element [id].
  const ElementEditCommand(this.id);

  /// The target element's id.
  final String id;

  /// The typed transform, invoked only when the element with [id] is an [E].
  E edit(E element);

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition, id, (ReportElement e) => e is E ? edit(e) : e),
      );
}
