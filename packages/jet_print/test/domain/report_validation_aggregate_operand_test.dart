/// Schema-aware I8 operand resolution tests (spec 033, Task 7).
///
/// Validates that `validate(def, schema: s)` flags ambiguous and not-found
/// aggregate operands in sink bands, while:
///   - passing same-scope and unique-descend operands;
///   - skipping the not-found error for published-total names (spec 030);
///   - `validate(def)` (no schema) leaves all structural checks intact but
///     adds NO operand diagnostics (backward compatible).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';
import 'package:jet_print/src/domain/scope_total.dart';

// ---------------------------------------------------------------------------
// Schema: Customer ▸ Order ▸ Line
// ---------------------------------------------------------------------------

/// Customer ▸ Order ▸ Line schema.
///
///   customer { customerId, customerName, orders: [ { orderId, orderDate,
///     lines: [ { lineId, lineTotal, qty } ] } ] }
///
/// `lineTotal` appears only under orders.lines (unique descend from the root).
/// `orderId`   appears only under orders (unique descend from root, same scope
///             for an orders-footer).
/// `customerId` is at the root master scope (same scope for a summary band).
const JetDataSchema _schema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerId', type: JetFieldType.integer),
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderId', type: JetFieldType.integer),
        FieldDef('orderDate', type: JetFieldType.dateTime),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('lineId', type: JetFieldType.integer),
            FieldDef('lineTotal', type: JetFieldType.double),
            FieldDef('qty', type: JetFieldType.integer),
          ],
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Helper builders
// ---------------------------------------------------------------------------

TextElement _txt(String id, {required String expression}) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 60, height: 12),
      text: id,
      expression: expression,
    );

Band _band(String id, BandType type, {List<ReportElement> elements = const []}) =>
    Band(id: id, type: type, height: 20, elements: elements);

/// Minimal report: summary band with [summaryExpr], customer group footer with
/// [customerFooterExpr], orders nested scope with [ordersFooterExpr] and a
/// lines nested scope inside orders. Optional [customerTotals] lets us declare
/// a ScopeTotal on the orders scope (published onto the customer row).
ReportDefinition _report({
  String? summaryExpr,
  String? customerFooterExpr,
  String? ordersFooterExpr,
  List<ScopeTotal> ordersTotals = const [],
}) {
  // lines scope (leaf)
  const DetailScope linesScope = DetailScope(
    id: 'lines',
    collectionField: 'lines',
    children: <ScopeNode>[
      BandNode(Band(id: 'lines/detail', type: BandType.detail, height: 12)),
    ],
  );

  // orders scope
  final DetailScope ordersScope = DetailScope(
    id: 'orders',
    collectionField: 'orders',
    children: <ScopeNode>[
      BandNode(
          Band(id: 'orders/detail', type: BandType.detail, height: 12)),
      const NestedScope(linesScope),
    ],
    footer: ordersFooterExpr == null
        ? null
        : _band('orders/footer', BandType.groupFooter,
            elements: [_txt('orders/footer/t', expression: ordersFooterExpr)]),
    totals: ordersTotals,
  );

  // root scope with a customer group
  final DetailScope root = DetailScope(
    id: 'root',
    children: <ScopeNode>[
      NestedScope(ordersScope),
    ],
    groups: customerFooterExpr == null
        ? const []
        : <GroupLevel>[
            GroupLevel(
              id: 'g0',
              name: 'customer',
              key: r'$F{customerId}',
              footer: _band('g0/footer', BandType.groupFooter,
                  elements: [
                    _txt('g0/footer/t', expression: customerFooterExpr)
                  ]),
            ),
          ],
  );

  return ReportDefinition(
    name: 'T',
    page: PageFormat.a4Portrait,
    furniture: const PageFurniture(),
    body: ReportBody(
      summary: summaryExpr == null
          ? null
          : _band('summary', BandType.summary,
              elements: [_txt('summary/t', expression: summaryExpr)]),
      root: root,
    ),
  );
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

bool _hasError(List<Diagnostic> ds, String needle) => ds.any((Diagnostic d) =>
    d.severity == DiagnosticSeverity.error &&
    d.message.toLowerCase().contains(needle.toLowerCase()));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('validate — schema-aware I8 operand resolution', () {
    // ------------------------------------------------------------------
    // Backward compatibility: no schema → no operand diagnostics
    // ------------------------------------------------------------------

    test('no schema: unique-descend operand causes no operand diagnostic', () {
      final def = _report(summaryExpr: r'SUM($F{lineTotal})');
      final ds = validate(def);
      // No operand errors — the structural I8 check still runs but passes
      // (summary is a supported sink).
      expect(ds.where((d) => d.message.contains('operand')), isEmpty);
    });

    test('no schema: ambiguous-looking operand causes no operand diagnostic', () {
      final def = _report(summaryExpr: r'SUM($F{lineTotal})');
      // Without a schema we can't detect ambiguity — no error.
      final ds = validate(def);
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    test(
        'no schema: unknown operand causes no operand diagnostic (backward compat)',
        () {
      final def = _report(summaryExpr: r'SUM($F{doesNotExist})');
      final ds = validate(def);
      expect(ds.where((d) => d.message.contains('operand')), isEmpty);
    });

    // ------------------------------------------------------------------
    // With schema: valid cases → no diagnostics
    // ------------------------------------------------------------------

    test('schema: unique-descend lineTotal at summary → no diagnostic', () {
      final def = _report(summaryExpr: r'SUM($F{lineTotal})');
      final ds = validate(def, schema: _schema);
      // lineTotal is unique in the Customer ▸ Order ▸ Line tree.
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    test('schema: same-scope customerId at summary → no diagnostic', () {
      final def = _report(summaryExpr: r'SUM($F{customerId})');
      final ds = validate(def, schema: _schema);
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    test(
        'schema: unique-descend lineTotal at root group footer → no diagnostic',
        () {
      final def =
          _report(customerFooterExpr: r'SUM($F{lineTotal})');
      final ds = validate(def, schema: _schema);
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    test('schema: same-scope orderId at orders nested footer → no diagnostic',
        () {
      // orderId is in the orders scope; the orders footer resolves against
      // orders.lines fields (one level descended).
      final def = _report(ordersFooterExpr: r'SUM($F{orderId})');
      final ds = validate(def, schema: _schema);
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    test(
        'schema: unique-descend lineTotal at orders nested footer → no diagnostic',
        () {
      final def = _report(ordersFooterExpr: r'SUM($F{lineTotal})');
      final ds = validate(def, schema: _schema);
      expect(ds.where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
    });

    // ------------------------------------------------------------------
    // With schema: ambiguous → error
    // ------------------------------------------------------------------

    test('schema: ambiguous operand (name in two sibling collections) → error',
        () {
      // Build a schema where `price` appears in both `widgets` and `gadgets`
      // sub-collections of the root, making it ambiguous.
      const JetDataSchema ambiguousSchema = JetDataSchema(
        name: 'Ambiguous',
        fields: <FieldDef>[
          FieldDef('id', type: JetFieldType.integer),
          FieldDef(
            'widgets',
            type: JetFieldType.collection,
            fields: <FieldDef>[
              FieldDef('price', type: JetFieldType.double),
            ],
          ),
          FieldDef(
            'gadgets',
            type: JetFieldType.collection,
            fields: <FieldDef>[
              FieldDef('price', type: JetFieldType.double),
            ],
          ),
        ],
      );

      // A simple report with just a summary band using the ambiguous operand.
      final def = ReportDefinition(
        name: 'AmbiguousReport',
        page: PageFormat.a4Portrait,
        furniture: const PageFurniture(),
        body: ReportBody(
          summary: _band('summary', BandType.summary,
              elements: [_txt('s/t', expression: r'SUM($F{price})')]),
          root: const DetailScope(id: 'root'),
        ),
      );

      final ds = validate(def, schema: ambiguousSchema);
      expect(_hasError(ds, 'ambiguous'), isTrue,
          reason: 'Expected an ambiguous-operand error; got: $ds');
    });

    // ------------------------------------------------------------------
    // With schema: not-found → error (unless published total)
    // ------------------------------------------------------------------

    test('schema: genuinely unknown operand at summary → error', () {
      final def = _report(summaryExpr: r'SUM($F{typoField})');
      final ds = validate(def, schema: _schema);
      expect(_hasError(ds, 'not found'), isTrue,
          reason: 'Expected a not-found operand error; got: $ds');
    });

    test('schema: unknown operand at root group footer → error', () {
      final def = _report(customerFooterExpr: r'SUM($F{typoField})');
      final ds = validate(def, schema: _schema);
      expect(_hasError(ds, 'not found'), isTrue,
          reason: 'Expected a not-found operand error; got: $ds');
    });

    // ------------------------------------------------------------------
    // Published-total exclusion: not-found but declared ScopeTotal → no error
    // ------------------------------------------------------------------

    test(
        'schema: published-total operand (ScopeTotal name) at summary → no error',
        () {
      // `orderTotal` is published by the orders scope as a ScopeTotal.
      // When SUM($F{orderTotal}) appears in the summary band, it is valid
      // even though `orderTotal` is not in the schema.
      final def = _report(
        summaryExpr: r'SUM($F{orderTotal})',
        ordersTotals: const [
          ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
        ],
      );
      final ds = validate(def, schema: _schema);
      expect(
          ds.where((d) =>
              d.severity == DiagnosticSeverity.error &&
              d.message.contains('orderTotal')),
          isEmpty,
          reason: 'Published-total operand must not produce a not-found error; '
              'got: $ds');
    });
  });
}
