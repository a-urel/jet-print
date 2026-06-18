import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/scope_total.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/value_type.dart';

TextElement _txt(String id, {String? expression}) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
      text: id,
      expression: expression,
    );

/// A representative definition: furniture (incl. reserved slots) + title/summary
/// + a grouped master scope with a nested `lines` scope and a deeper `notes`
/// scope, plus parameters and a group-scoped variable.
ReportDefinition _representative() => ReportDefinition(
      name: 'Everything',
      page: PageFormat.a4Portrait,
      parameters: const <ReportParameter>[
        ReportParameter(name: 'asOf', type: JetFieldType.dateTime),
      ],
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'lineSum',
          expression: r'$F{lineTotal}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'root/g0',
        ),
      ],
      furniture: PageFurniture(
        pageHeader: Band(
            id: 'furniture/pageHeader',
            type: BandType.pageHeader,
            height: 20,
            elements: <ReportElement>[_txt('rt')]),
        pageFooter: Band(
            id: 'furniture/pageFooter',
            type: BandType.pageFooter,
            height: 20,
            elements: <ReportElement>[
              _txt('pn',
                  expression:
                      r'"Page " + $V{PAGE_NUMBER} + "/" + $V{PAGE_COUNT}')
            ]),
        columnHeader: const Band(
            id: 'furniture/columnHeader',
            type: BandType.columnHeader,
            height: 14),
        background: const Band(
            id: 'furniture/background', type: BandType.background, height: 0),
      ),
      body: ReportBody(
        title: Band(
            id: 'body/title',
            type: BandType.title,
            height: 24,
            elements: <ReportElement>[_txt('t')]),
        summary:
            const Band(id: 'body/summary', type: BandType.summary, height: 24),
        noData:
            const Band(id: 'body/noData', type: BandType.noData, height: 30),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'root/g0',
              name: 'invoice',
              key: r'$F{invoiceNo}',
              keepTogether: true,
              startNewPage: true,
              header: Band(
                  id: 'root/g0/header',
                  type: BandType.groupHeader,
                  height: 40,
                  elements: <ReportElement>[
                    _txt('gh', expression: r'$F{invoiceNo}')
                  ]),
              footer: const Band(
                  id: 'root/g0/footer', type: BandType.groupFooter, height: 20),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 18,
                elements: <ReportElement>[_txt('meta')])),
            NestedScope(DetailScope(
              id: 'root/c1',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'root/c1/c0',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[
                      _txt('line', expression: r'$F{description}')
                    ])),
                NestedScope(DetailScope(
                  id: 'root/c1/c1',
                  collectionField: 'notes',
                  footer: Band(
                      id: 'root/c1/c1/footer',
                      type: BandType.groupFooter,
                      height: 14,
                      elements: <ReportElement>[
                        _txt('notesTotal', expression: r'$V{notesSum}')
                      ]),
                  children: <ScopeNode>[
                    BandNode(Band(
                        id: 'root/c1/c1/c0',
                        type: BandType.detail,
                        height: 12)),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  group('ReportDefinition codec v2', () {
    test('round-trips losslessly (decode(encode(def)) == def)', () {
      final ReportDefinition def = _representative();
      final ReportDefinition back = JetReportFormat.decodeDefinition(
          JetReportFormat.encodeDefinition(def));
      expect(back, equals(def));
    });

    test('stamps schemaVersion 2', () {
      expect(
          JetReportFormat.encodeDefinition(_representative())['schemaVersion'],
          2);
    });

    test('round-trips a minimal definition (only a root scope)', () {
      const ReportDefinition def = ReportDefinition(
        name: 'Min',
        page: PageFormat.a4Portrait,
        body: ReportBody(root: DetailScope(id: 'root')),
      );
      expect(
          JetReportFormat.decodeDefinition(
              JetReportFormat.encodeDefinition(def)),
          equals(def));
    });

    test('survives a JSON string round-trip', () {
      final ReportDefinition def = _representative();
      expect(
          JetReportFormat.decodeDefinitionJson(
              JetReportFormat.encodeDefinitionJson(def)),
          equals(def));
    });

    test('round-trips a nested scope footer (spec 029)', () {
      const ReportDefinition def = ReportDefinition(
        name: 'Footer',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'root/c0',
                collectionField: 'lines',
                footer: Band(
                    id: 'root/c0/footer',
                    type: BandType.groupFooter,
                    height: 14),
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'root/c0/c0', type: BandType.detail, height: 10)),
                ],
              )),
            ],
          ),
        ),
      );
      final ReportDefinition back = JetReportFormat.decodeDefinition(
          JetReportFormat.encodeDefinition(def));
      expect(back, equals(def));
      final NestedScope nested = back.body.root.children.single as NestedScope;
      expect(
          nested.scope.footer,
          const Band(
              id: 'root/c0/footer', type: BandType.groupFooter, height: 14));
    });

    test('decodes a scope with no footer key as footer == null (back-compat)',
        () {
      final ReportDefinition back =
          JetReportFormat.decodeDefinition(<String, Object?>{
        'schemaVersion': 2,
        'name': 'x',
        'page': PageFormat.a4Portrait.toJson(),
        'body': <String, Object?>{
          'root': <String, Object?>{
            'id': 'root',
            'children': <Object?>[
              <String, Object?>{
                'kind': 'scope',
                'scope': <String, Object?>{
                  'id': 'root/c0',
                  'collectionField': 'lines',
                },
              },
            ],
          },
        },
      });
      final NestedScope nested = back.body.root.children.single as NestedScope;
      expect(nested.scope.footer, isNull);
    });

    test('a scope without a footer omits the "footer" key', () {
      final Map<String, Object?> json = JetReportFormat.encodeDefinition(
        const ReportDefinition(
          name: 'x',
          page: PageFormat.a4Portrait,
          body: ReportBody(root: DetailScope(id: 'root')),
        ),
      );
      final Map<Object?, Object?> root = (json['body']! as Map)['root']! as Map;
      expect(root.containsKey('footer'), isFalse);
    });

    test('round-trips nested scope totals (spec 030, B2)', () {
      const ReportDefinition def = ReportDefinition(
        name: 'Totals',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'root/c0',
                collectionField: 'lines',
                totals: <ScopeTotal>[
                  ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ScopeTotal('orderCount', r'COUNT($F{lineTotal})'),
                ],
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'root/c0/c0', type: BandType.detail, height: 10)),
                ],
              )),
            ],
          ),
        ),
      );
      final ReportDefinition back = JetReportFormat.decodeDefinition(
          JetReportFormat.encodeDefinition(def));
      expect(back, equals(def));
      final NestedScope nested = back.body.root.children.single as NestedScope;
      expect(nested.scope.totals, const <ScopeTotal>[
        ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
        ScopeTotal('orderCount', r'COUNT($F{lineTotal})'),
      ]);
    });

    test('decodes a scope with no totals key as totals == [] (back-compat)',
        () {
      final ReportDefinition back =
          JetReportFormat.decodeDefinition(<String, Object?>{
        'schemaVersion': 2,
        'name': 'x',
        'page': PageFormat.a4Portrait.toJson(),
        'body': <String, Object?>{
          'root': <String, Object?>{
            'id': 'root',
            'children': <Object?>[
              <String, Object?>{
                'kind': 'scope',
                'scope': <String, Object?>{
                  'id': 'root/c0',
                  'collectionField': 'lines',
                },
              },
            ],
          },
        },
      });
      final NestedScope nested = back.body.root.children.single as NestedScope;
      expect(nested.scope.totals, const <ScopeTotal>[]);
    });

    Map<String, Object?> defWithTotals(Object? totals) => <String, Object?>{
          'schemaVersion': 2,
          'name': 'x',
          'page': PageFormat.a4Portrait.toJson(),
          'body': <String, Object?>{
            'root': <String, Object?>{
              'id': 'root',
              'totals': totals,
            },
          },
        };

    test('rejects a non-list "totals"', () {
      expect(
        () => JetReportFormat.decodeDefinition(
            defWithTotals(<String, Object?>{'name': 'x'})),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('rejects a non-map "totals" entry', () {
      expect(
        () => JetReportFormat.decodeDefinition(
            defWithTotals(<Object?>['not a map'])),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('rejects a "totals" entry missing "name"', () {
      expect(
        () => JetReportFormat.decodeDefinition(defWithTotals(<Object?>[
          <String, Object?>{'expression': r'SUM($F{lineTotal})'},
        ])),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('rejects a "totals" entry missing "expression"', () {
      expect(
        () => JetReportFormat.decodeDefinition(defWithTotals(<Object?>[
          <String, Object?>{'name': 'orderTotal'},
        ])),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('a scope without totals omits the "totals" key', () {
      final Map<String, Object?> json = JetReportFormat.encodeDefinition(
        const ReportDefinition(
          name: 'x',
          page: PageFormat.a4Portrait,
          body: ReportBody(root: DetailScope(id: 'root')),
        ),
      );
      final Map<Object?, Object?> root = (json['body']! as Map)['root']! as Map;
      expect(root.containsKey('totals'), isFalse);
    });

    test('fail-fasts on a missing schemaVersion', () {
      expect(
        () => JetReportFormat.decodeDefinition(
            <String, Object?>{'name': 'x', 'body': <String, Object?>{}}),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('fail-fasts on a schemaVersion newer than this build', () {
      expect(
        () => JetReportFormat.decodeDefinition(<String, Object?>{
          'schemaVersion': 99,
          'name': 'x',
          'page': PageFormat.a4Portrait.toJson(),
          'body': <String, Object?>{
            'root': <String, Object?>{'id': 'root'}
          },
        }),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('Band.columnLayout round-trips and is omitted when null (spec 034)', () {
      const ColumnLayout grid = ColumnLayout(
          columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
      final ReportDefinition def = ReportDefinition(
        name: 'labels',
        page: PageFormat.a4Portrait,
        body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(
                id: 'd', type: BandType.detail, height: 80, columnLayout: grid)),
          ]),
        ),
      );

      final Map<String, Object?> json = JetReportFormat.encodeDefinition(def);
      expect(JetReportFormat.decodeDefinition(json), def);

      // Absent when null: a plain band emits no 'columnLayout' key.
      final Map<String, Object?> plain = JetReportFormat.encodeDefinition(
        ReportDefinition(
          name: 'plain',
          page: PageFormat.a4Portrait,
          body: const ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[
              BandNode(Band(id: 'd', type: BandType.detail, height: 80)),
            ]),
          ),
        ),
      );
      final Map<String, Object?> rootScope =
          (plain['body']! as Map)['root']! as Map<String, Object?>;
      final Map<String, Object?> bandJson =
          ((rootScope['children']! as List).single as Map)['band']
              as Map<String, Object?>;
      expect(bandJson.containsKey('columnLayout'), isFalse);
    });
  });
}
