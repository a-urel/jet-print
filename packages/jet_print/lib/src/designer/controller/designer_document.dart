/// An immutable snapshot of the editable design: model + selection.
library;

import '../../domain/report_definition.dart';
import 'selection.dart';

/// The unit of undo/redo history: the current [definition] paired with the
/// [selection] that was active for it.
///
/// Because both members are immutable, capturing a snapshot is O(1) and
/// restoring one is exact — undoing a model edit also restores the selection
/// that existed before it (FR-017, the coherent-selection guarantee).
///
/// Reification (spec 024): the model is now a [ReportDefinition] section tree,
/// not a flat `ReportTemplate`.
class DesignerDocument {
  /// Creates a snapshot pairing [definition] with [selection].
  const DesignerDocument({required this.definition, required this.selection});

  /// The report model at this point in history.
  final ReportDefinition definition;

  /// The selection active for [definition].
  final Selection selection;

  /// Returns a copy with the selection replaced (model unchanged).
  DesignerDocument withSelection(Selection selection) =>
      DesignerDocument(definition: definition, selection: selection);

  /// Returns a copy with the model (and optionally [selection]) replaced.
  DesignerDocument withDefinition(ReportDefinition definition,
          {Selection? selection}) =>
      DesignerDocument(
        definition: definition,
        selection: selection ?? this.selection,
      );
}
