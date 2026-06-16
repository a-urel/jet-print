// Author-time field resolution accounting for spec-030 published totals and the
// spec-029 nested-footer parent/child duality. Drives the same band-walk +
// schema seam the Properties panel will, over a 3-level nested-list shape
// (customers ▸ orders ▸ lines) whose published totals (orderTotal, customerTotal)
// are NOT in the data schema — they're injected at fill time onto parent rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/designer/controller/binding_resolution.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/scope_total.dart';

/// customers ▸ orders ▸ lines — real fields only; NO orderTotal/customerTotal
/// (those are published totals, injected at fill time, not schema fields).
const JetDataSchema _schema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderNo', type: JetFieldType.string),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('description', type: JetFieldType.string),
            FieldDef('lineTotal', type: JetFieldType.double),
          ],
        ),
      ],
    ),
  ],
);

Band _band(String id, BandType type) => Band(id: id, type: type, height: 20);

/// root (customer GroupLevel + customer footer showing [customerTotal])
///   └─ NestedScope orders (totals: customerTotal = SUM($F{orderTotal}))
///        ├─ order detail band 'orderRow'
///        └─ NestedScope lines (totals: orderTotal = SUM($F{lineTotal});
///             footer 'lf' showing $F{orderTotal})
///             └─ line detail band 'lineRow'
/// plus body.summary 'summary' showing {SUM([customerTotal])} (stored
/// SUM($F{customerTotal})).
ReportDefinition _def() => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: _band('summary', BandType.summary),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'root/customer',
              name: 'customer',
              key: r'$F{customerName}',
              header: _band('ch', BandType.groupHeader),
              footer: _band('cf', BandType.groupFooter),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              totals: <ScopeTotal>[
                ScopeTotal('customerTotal', r'SUM($F{orderTotal})'),
              ],
              children: <ScopeNode>[
                BandNode(_band('orderRow', BandType.detail)),
                NestedScope(DetailScope(
                  id: 'lines',
                  collectionField: 'lines',
                  totals: <ScopeTotal>[
                    ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ],
                  footer: _band('lf', BandType.detail),
                  children: <ScopeNode>[
                    BandNode(_band('lineRow', BandType.detail)),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  group('resolvableNamesForBand', () {
    final ReportDefinition def = _def();

    test('summary band sees customerTotal, not orderTotal', () {
      final Set<String> names = resolvableNamesForBand(def, _schema, 'summary');
      expect(names, contains('customerTotal'));
      expect(names, isNot(contains('orderTotal')));
    });

    test('customer group footer sees customerTotal', () {
      // cf renders at root scope; orders (its direct child) publishes
      // customerTotal onto the root rows.
      expect(resolvableNamesForBand(def, _schema, 'cf'),
          contains('customerTotal'));
    });

    test('order detail band sees orderTotal, not customerTotal', () {
      final Set<String> names =
          resolvableNamesForBand(def, _schema, 'orderRow');
      expect(names, contains('orderTotal'));
      expect(names, isNot(contains('customerTotal')));
    });

    test('lines footer sees lineTotal AND orderTotal, not customerTotal', () {
      // 'lf' is the lines-scope footer: it renders at its PARENT (orders) row but
      // aggregates over its own (lines) collection — so it sees the union of the
      // lines scope (lineTotal) and the orders scope (orderTotal, published by
      // lines onto orders rows). It must NOT see customerTotal (SC-004).
      final Set<String> names = resolvableNamesForBand(def, _schema, 'lf');
      expect(names, contains('lineTotal'));
      expect(names, contains('orderTotal'));
      expect(names, isNot(contains('customerTotal')));
    });

    test('no band resolves a bogus name', () {
      for (final String id in <String>['summary', 'cf', 'orderRow', 'lf']) {
        expect(
            resolvableNamesForBand(def, _schema, id), isNot(contains('nope')));
      }
    });
  });

  group('resolvableFieldChoices', () {
    final ReportDefinition def = _def();

    FieldDef? byName(List<FieldDef> fs, String name) {
      for (final FieldDef f in fs) {
        if (f.name == name) return f;
      }
      return null;
    }

    test('summary includes customerTotal as a double', () {
      final List<FieldDef> choices =
          resolvableFieldChoices(def, _schema, 'summary');
      final FieldDef? ct = byName(choices, 'customerTotal');
      expect(ct, isNotNull);
      expect(ct!.type, JetFieldType.double);
    });

    test(
        'lines footer includes orderTotal (double) + line fields, no collections',
        () {
      final List<FieldDef> choices = resolvableFieldChoices(def, _schema, 'lf');
      final FieldDef? ot = byName(choices, 'orderTotal');
      expect(ot, isNotNull);
      expect(ot!.type, JetFieldType.double);
      expect(byName(choices, 'lineTotal')?.type, JetFieldType.double);
      // Collection-typed fields are excluded from value-field choices.
      expect(choices.every((FieldDef f) => f.type != JetFieldType.collection),
          isTrue);
    });
  });
}
