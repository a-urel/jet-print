import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../region_chrome.dart';

/// Body of the **Data Source** tab: the bound dataset presented as a three-level
/// explorer tree — database → tables/collections → fields — that a report would
/// bind elements against (FR-007). Database and table nodes expand and collapse;
/// each field carries an icon chosen for its data type. Unlike the other right
/// panels this body intentionally has no header/title or hint text: the tree is
/// the panel, and the owning tab already names it.
///
/// The database, table and field names are illustrative sample data and are
/// intentionally NOT translated (only chrome is localized).
class DataSourcePanel extends StatelessWidget {
  /// Creates the Data Source panel body. Private to the library.
  const DataSourcePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[_databaseNode(_sampleDatabase)],
      ),
    );
  }
}

/// Builds the database root branch (expanded), listing its tables. The first
/// table opens so the typed-field shape is visible at a glance; later tables
/// start collapsed to advertise the expand affordance.
Widget _databaseNode(_Database database) {
  return TreeBranch(
    icon: LucideIcons.database,
    label: database.name,
    depth: 0,
    children: <Widget>[
      for (int i = 0; i < database.tables.length; i++)
        TreeBranch(
          icon: LucideIcons.table2,
          label: database.tables[i].name,
          depth: 1,
          initiallyExpanded: i == 0,
          children: <Widget>[
            for (final _Field field in database.tables[i].fields)
              _FieldRow(field: field, depth: 2),
          ],
        ),
    ],
  );
}

// --- Sample dataset (illustrative placeholder, not localized) ---------------

/// One database exposed to the report, holding tables/collections.
class _Database {
  const _Database(this.name, this.tables);

  final String name;
  final List<_Table> tables;
}

/// One table/collection, holding typed fields.
class _Table {
  const _Table(this.name, this.fields);

  final String name;
  final List<_Field> fields;
}

/// One field: a name plus the data [type] that picks its glyph.
class _Field {
  const _Field(this.name, this.type);

  final String name;
  final _FieldType type;
}

/// The data types a field can have, each paired with the label shown on the row
/// and the icon that signals the type at a glance.
enum _FieldType {
  text('String', LucideIcons.type),
  integer('Int32', LucideIcons.hash),
  decimal('Decimal', LucideIcons.calculator),
  dateTime('DateTime', LucideIcons.calendarClock),
  boolean('Boolean', LucideIcons.toggleLeft);

  const _FieldType(this.label, this.icon);

  /// The short type caption shown trailing the field name.
  final String label;

  /// The glyph that signals this data type.
  final IconData icon;
}

const _Database _sampleDatabase = _Database('SalesDB', <_Table>[
  _Table('Orders', <_Field>[
    _Field('OrderID', _FieldType.integer),
    _Field('CustomerName', _FieldType.text),
    _Field('OrderDate', _FieldType.dateTime),
    _Field('Total', _FieldType.decimal),
    _Field('Status', _FieldType.text),
    _Field('ShippedDate', _FieldType.dateTime),
  ]),
  _Table('Customers', <_Field>[
    _Field('CustomerID', _FieldType.integer),
    _Field('Name', _FieldType.text),
    _Field('Email', _FieldType.text),
    _Field('IsActive', _FieldType.boolean),
  ]),
]);

// --- Field rows -------------------------------------------------------------

/// A leaf field row: its data-type glyph, the field name, and the type label.
/// Branch (database/table) rows come from the shared [TreeBranch].
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.depth});

  final _Field field;
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
          Icon(field.type.icon, size: 14, color: colors.mutedForeground),
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
            field.type.label,
            style: theme.textTheme.muted.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
