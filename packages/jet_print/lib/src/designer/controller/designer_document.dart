/// An immutable snapshot of the editable design: model + selection.
library;

import '../../domain/report_template.dart';
import 'selection.dart';

/// The unit of undo/redo history: the current [template] paired with the
/// [selection] that was active for it.
///
/// Because both members are immutable, capturing a snapshot is O(1) and
/// restoring one is exact — undoing a model edit also restores the selection
/// that existed before it (FR-017, the coherent-selection guarantee).
class DesignerDocument {
  /// Creates a snapshot pairing [template] with [selection].
  const DesignerDocument({required this.template, required this.selection});

  /// The report model at this point in history.
  final ReportTemplate template;

  /// The selection active for [template].
  final Selection selection;

  /// Returns a copy with the selection replaced (model unchanged).
  DesignerDocument withSelection(Selection selection) =>
      DesignerDocument(template: template, selection: selection);

  /// Returns a copy with the model (and optionally [selection]) replaced.
  DesignerDocument withTemplate(ReportTemplate template,
          {Selection? selection}) =>
      DesignerDocument(
        template: template,
        selection: selection ?? this.selection,
      );
}
