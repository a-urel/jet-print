// Descendant operand names + field choices for a band (spec-033).
//
// Builds a Customer ▸ Order ▸ Line report (master = customers; a root
// `customer` group with footer 'cf'; summary band 'summary') and checks that
// the two new helpers return exactly the leaf names uniquely reachable by
// descending the band's own scope (DescendPath), NOT same-scope fields or
// collection names, and NOT ambiguous names when two sibling collections share
// a leaf name.
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

// ---------------------------------------------------------------------------
// Schema: root has customerCode + orders[orderNo, lines[lineTotal]].
// ---------------------------------------------------------------------------
const JetDataSchema _schema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerCode', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderNo', type: JetFieldType.string),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('lineTotal', type: JetFieldType.double),
          ],
        ),
      ],
    ),
  ],
);

Band _band(String id, BandType type) => Band(id: id, type: type, height: 20);

// ---------------------------------------------------------------------------
// Report: root scope (customerCode, orders collection)
//   root GroupLevel 'customer' → footer 'cf'
//   NestedScope orders
//     BandNode orderRow
//     NestedScope lines
//       BandNode lineRow
// summary band 'summary' at root
// ---------------------------------------------------------------------------
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
              key: r'$F{customerCode}',
              header: _band('ch', BandType.groupHeader),
              footer: _band('cf', BandType.groupFooter),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              totals: const <ScopeTotal>[],
              children: <ScopeNode>[
                BandNode(_band('orderRow', BandType.detail)),
                NestedScope(DetailScope(
                  id: 'lines',
                  collectionField: 'lines',
                  totals: const <ScopeTotal>[],
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

// ---------------------------------------------------------------------------
// Ambiguous schema: root has two sibling collections that both contain a
// leaf named 'amount', so 'amount' resolves to Ambiguous (two DescendPaths).
// ---------------------------------------------------------------------------
const JetDataSchema _ambiguousSchema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerCode', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ],
    ),
    FieldDef(
      'payments',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ],
    ),
  ],
);

ReportDefinition _ambiguousDef() => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: _band('summary2', BandType.summary),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              totals: const <ScopeTotal>[],
              children: const <ScopeNode>[
                BandNode(Band(id: 'orderRow2', type: BandType.detail, height: 20)),
              ],
            )),
            NestedScope(DetailScope(
              id: 'payments',
              collectionField: 'payments',
              totals: const <ScopeTotal>[],
              children: const <ScopeNode>[
                BandNode(Band(id: 'payRow', type: BandType.detail, height: 20)),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  group('descendantOperandNamesForBand', () {
    final ReportDefinition def = _def();

    test('summary band contains lineTotal and orderNo', () {
      final Set<String> names =
          descendantOperandNamesForBand(def, _schema, 'summary');
      expect(names, contains('lineTotal'));
      expect(names, contains('orderNo'));
    });

    test('summary band does NOT contain customerCode (same-scope)', () {
      final Set<String> names =
          descendantOperandNamesForBand(def, _schema, 'summary');
      expect(names, isNot(contains('customerCode')));
    });

    test('summary band does NOT contain collection names orders/lines', () {
      final Set<String> names =
          descendantOperandNamesForBand(def, _schema, 'summary');
      expect(names, isNot(contains('orders')));
      expect(names, isNot(contains('lines')));
    });

    test('root group footer cf has same descendant set as summary', () {
      // cf is at root scope — same scope chain as summary
      final Set<String> cfNames =
          descendantOperandNamesForBand(def, _schema, 'cf');
      final Set<String> summaryNames =
          descendantOperandNamesForBand(def, _schema, 'summary');
      expect(cfNames, equals(summaryNames));
    });

    test('ambiguous name is absent from descendant names', () {
      final ReportDefinition ambDef = _ambiguousDef();
      final Set<String> names =
          descendantOperandNamesForBand(ambDef, _ambiguousSchema, 'summary2');
      expect(names, isNot(contains('amount')));
    });
  });

  group('descendantFieldChoicesForBand', () {
    final ReportDefinition def = _def();

    test('returns FieldDefs for exactly the descendant operand set', () {
      final Set<String> expectedNames =
          descendantOperandNamesForBand(def, _schema, 'summary');
      final List<FieldDef> choices =
          descendantFieldChoicesForBand(def, _schema, 'summary');
      final Set<String> choiceNames =
          choices.map((FieldDef f) => f.name).toSet();
      expect(choiceNames, equals(expectedNames));
    });

    test('cf field choices match summary field choices', () {
      final List<FieldDef> cfChoices =
          descendantFieldChoicesForBand(def, _schema, 'cf');
      final List<FieldDef> summaryChoices =
          descendantFieldChoicesForBand(def, _schema, 'summary');
      final Set<String> cfNames = cfChoices.map((FieldDef f) => f.name).toSet();
      final Set<String> summaryNames =
          summaryChoices.map((FieldDef f) => f.name).toSet();
      expect(cfNames, equals(summaryNames));
    });

    test('ambiguous name is absent from field choices', () {
      final ReportDefinition ambDef = _ambiguousDef();
      final List<FieldDef> choices =
          descendantFieldChoicesForBand(ambDef, _ambiguousSchema, 'summary2');
      expect(choices.map((FieldDef f) => f.name), isNot(contains('amount')));
    });
  });
}
