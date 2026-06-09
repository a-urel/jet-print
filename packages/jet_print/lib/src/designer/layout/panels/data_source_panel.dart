import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../designer_schema_scope.dart';
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
      return RegionEmptyHint(
        icon: LucideIcons.database,
        message: JetPrintLocalizations.of(context).dataSourceEmpty,
      );
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

/// Builds the dataset root branch (expanded), listing its root fields.
Widget _datasetNode(JetDataSchema schema) {
  return TreeBranch(
    icon: LucideIcons.database,
    label: schema.name,
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
      icon: _glyphFor(JetFieldType.collection),
      label: field.name,
      depth: depth,
      // Collections start collapsed so deep structures don't flood the panel;
      // the disclosure chevron advertises that children are inside.
      initiallyExpanded: false,
      children: <Widget>[
        for (final FieldDef child in field.fields) _fieldNode(child, depth + 1),
      ],
    );
  }
  return _FieldRow(field: field, depth: depth);
}

/// The glyph that signals a field's [JetFieldType] at a glance.
IconData _glyphFor(JetFieldType type) => switch (type) {
      JetFieldType.string => LucideIcons.type,
      JetFieldType.integer => LucideIcons.hash,
      JetFieldType.double => LucideIcons.calculator,
      JetFieldType.boolean => LucideIcons.toggleLeft,
      JetFieldType.dateTime => LucideIcons.calendarClock,
      JetFieldType.collection => LucideIcons.list,
      JetFieldType.unknown => LucideIcons.circleHelp,
    };

/// A short, technical type caption shown trailing a leaf field (not localized —
/// these are type tokens, like SQL types, not UI chrome). Empty for `unknown`.
String _labelFor(JetFieldType type) => switch (type) {
      JetFieldType.string => 'String',
      JetFieldType.integer => 'Integer',
      JetFieldType.double => 'Decimal',
      JetFieldType.boolean => 'Boolean',
      JetFieldType.dateTime => 'DateTime',
      JetFieldType.collection => 'Collection',
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
    return Padding(
      padding: EdgeInsets.only(
        left: treeRowInset(depth),
        top: 4,
        bottom: 4,
        right: 8,
      ),
      child: Row(
        children: <Widget>[
          Icon(_glyphFor(field.type), size: 14, color: colors.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              field.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small,
            ),
          ),
          Text(
            _labelFor(field.type),
            style: theme.textTheme.muted.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
