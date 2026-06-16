/// Detail-scope lifecycle + property commands (spec 024 / T031 / FR-015).
///
/// A [DetailScope] is a first-class, addressable iteration scope. Master/detail
/// nesting is expressed by adding a [NestedScope] child; the collection a scope
/// iterates is a property of the scope (not, as before, a band attribute).
library;

import '../../../domain/detail_scope.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Appends a nested [scope] to scope [parentScopeId]'s children and selects it.
class CreateScopeCommand extends EditCommand {
  /// Creates an add of [scope] under [parentScopeId].
  const CreateScopeCommand({required this.parentScopeId, required this.scope});

  /// The stable id of the parent scope.
  final String parentScopeId;

  /// The new nested scope (id + collectionField already assigned).
  final DetailScope scope;

  @override
  String get label => 'Add scope';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        addScopeChild(before.definition, parentScopeId, NestedScope(scope)),
        selection: Selection.scope(scope.id),
      );
}

/// Removes the nested scope [scopeId] and clears the selection.
class DeleteScopeCommand extends EditCommand {
  /// Creates a delete of scope [scopeId].
  const DeleteScopeCommand(this.scopeId);

  /// The stable id of the nested scope to remove.
  final String scopeId;

  @override
  String get label => 'Delete scope';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        removeScope(before.definition, scopeId),
        selection: Selection.empty,
      );
}

/// Sets (or, when [collectionField] is null, clears) the nested collection a
/// scope iterates — the reified replacement for the old per-band collection
/// binding (US3 / FR-015, FR-015a). A no-op for an unknown scope or unchanged
/// value.
class SetScopeCollectionCommand extends EditCommand {
  /// Binds scope [scopeId] to [collectionField] (null clears it).
  const SetScopeCollectionCommand({
    required this.scopeId,
    required this.collectionField,
  });

  /// The stable id of the target scope.
  final String scopeId;

  /// The nested-collection field the scope iterates, or null to clear.
  final String? collectionField;

  @override
  String get label =>
      collectionField == null ? 'Clear scope collection' : 'Bind scope';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        mapScopes(
          before.definition,
          (DetailScope s) => s.id == scopeId
              // Build directly (not copyWith) so a null [collectionField] clears it.
              ? DetailScope(
                  id: s.id,
                  collectionField: collectionField,
                  groups: s.groups,
                  children: s.children,
                  // Rebinding (or clearing) the collection must not drop the
                  // scope's footer (spec 029) or published totals (spec 030).
                  footer: s.footer,
                  totals: s.totals,
                )
              : s,
        ),
      );
}
