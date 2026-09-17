/// Detail-scope lifecycle + property commands.
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
/// binding. A no-op for an unknown scope or unchanged
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
              // Built field-by-field. NOT because copyWith cannot clear a
              // nullable slot — since `copy_support.dart`'s thunks it can:
              // `s.copyWith(collectionField: () => collectionField)` would do.
              // Kept explicit so the six fields are visible at the one place
              // that rebinds a scope; the cost is that a NEW DetailScope field
              // must be added here too or it is silently dropped (the
              // "rebuilders drop fields silently" trap in AGENTS.md).
              ? DetailScope(
                  id: s.id,
                  collectionField: collectionField,
                  groups: s.groups,
                  children: s.children,
                  // Rebinding (or clearing) the collection must not drop the
                  // scope's footer or published totals.
                  footer: s.footer,
                  totals: s.totals,
                )
              : s,
        ),
      );
}
