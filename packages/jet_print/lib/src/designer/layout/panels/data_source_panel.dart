import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../canvas/field_drag_data.dart';
import '../../designer_schema_scope.dart';
import '../../field_type_glyph.dart';
import '../../l10n/jet_print_localizations.dart';
import '../region_chrome.dart';

/// Body of the **Data Source** tab: the host-attached [JetDataSchema] rendered
/// as an expandable explorer tree — dataset → fields — that report elements bind
/// against (FR-005..FR-007). A field of type [JetFieldType.collection] is a
/// branch whose children are its own fields, so a master/detail structure
/// (e.g. an invoice with a nested `lines` collection) nests to arbitrary depth.
///
/// When no schema is attached the panel shows a clear empty state (FR-008) — no
/// stale or placeholder field names. Field names come from the host's schema and
/// are intentionally NOT translated; only the empty-state message is localized.
class DataSourcePanel extends StatelessWidget {
  /// Creates the Data Source panel body. Private to the library.
  const DataSourcePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final JetDataSchema? schema = DesignerSchemaScope.of(context);
    if (schema == null) {
      final VoidCallback? onSelect =
          DesignerSchemaScope.selectCallbackOf(context);
      if (onSelect == null) {
        return RegionEmptyHint(
          icon: LucideIcons.database,
          message: JetPrintLocalizations.of(context).dataSourceEmpty,
        );
      }
      return _SelectDataSourcePrompt(onSelect: onSelect);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[_datasetNode(schema)],
      ),
    );
  }
}

/// Empty-state prompt shown when no data source is attached but the host wired
/// a select action: a short hint plus a "Select data source" button.
class _SelectDataSourcePrompt extends StatelessWidget {
  const _SelectDataSourcePrompt({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(LucideIcons.database,
                size: 28, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 12),
            Text(
              l10n.dataSourceEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
            const SizedBox(height: 16),
            ShadButton.outline(
              key: const ValueKey<String>('jet_print.dataSource.selectButton'),
              onPressed: onSelect,
              child: Text(l10n.dataSourceSelect),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds the dataset root branch (expanded), listing its root fields.
Widget _datasetNode(JetDataSchema schema) {
  return TreeBranch(
    icon: LucideIcons.database,
    label: schema.name,
    description: schema.description,
    depth: 0,
    children: <Widget>[
      for (final FieldDef field in schema.fields) _fieldNode(field, 1),
    ],
  );
}

/// One field at [depth]: a collapsible branch for a nested collection (its
/// children are the collection's own fields), or a leaf row for a scalar.
Widget _fieldNode(FieldDef field, int depth) {
  if (field.type == JetFieldType.collection) {
    return TreeBranch(
      icon: fieldTypeGlyph(JetFieldType.collection),
      label: field.name,
      depth: depth,
      description: field.description,
      // Collections start collapsed so deep structures don't flood the panel;
      // the disclosure chevron advertises that children are inside.
      initiallyExpanded: false,
      actions: const <Widget>[_CollectionActions()],
      children: <Widget>[
        for (final FieldDef child in field.fields) _fieldNode(child, depth + 1),
      ],
    );
  }
  return _FieldRow(field: field, depth: depth);
}

/// A short, technical type caption shown trailing a leaf field (not localized —
/// these are type tokens, like SQL types, not UI chrome). Empty for `unknown`.
String _labelFor(JetFieldType type) => switch (type) {
      JetFieldType.string => 'String',
      JetFieldType.integer => 'Integer',
      JetFieldType.double => 'Decimal',
      JetFieldType.boolean => 'Boolean',
      JetFieldType.dateTime => 'DateTime',
      JetFieldType.collection => 'List',
      JetFieldType.unknown => '',
    };

/// A leaf field row: its data-type glyph, the field name, and the type token.
/// Branch (dataset / collection) rows come from the shared [TreeBranch].
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.depth});

  final FieldDef field;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final Widget row = Padding(
      padding: EdgeInsets.only(
        left: treeRowInset(depth),
        top: 4,
        bottom: 4,
        right: 8,
      ),
      child: Row(
        children: <Widget>[
          Icon(fieldTypeGlyph(field.type),
              size: 14, color: colors.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: LabelWithDescription(
              label: field.name,
              description: field.description,
              theme: theme,
            ),
          ),
          Text(
            _labelFor(field.type),
            style: theme.textTheme.muted.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
    // Leaf fields are draggable onto the canvas to create a bound element
    // (FR-011). Collection (branch) nodes use TreeBranch and are never wrapped
    // here, so dropping one is a no-op by construction.
    return Draggable<FieldDragData>(
      data: FieldDragData(fieldName: field.name),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _FieldDragChip(name: field.name, theme: theme),
      child: row,
    );
  }
}

/// The little chip shown under the pointer while dragging a field. Carries an
/// explicit text style so it renders correctly in the drag Overlay (no Material
/// ancestor).
class _FieldDragChip extends StatelessWidget {
  const _FieldDragChip({required this.name, required this.theme});

  final String name;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    return Transform.translate(
      offset: const Offset(8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            name,
            style: TextStyle(
              color: colors.primaryForeground,
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing token on a Data Source collection field: its type caption,
/// matching the trailing token on scalar leaf rows ([_FieldRow]) so a list reads
/// as a typed field too.
class _CollectionActions extends StatelessWidget {
  const _CollectionActions();

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return Text(
      _labelFor(JetFieldType.collection),
      style: theme.textTheme.muted.copyWith(fontSize: 11),
    );
  }
}
