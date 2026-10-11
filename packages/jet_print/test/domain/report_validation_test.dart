import 'package:flutter_test/flutter_test.dart';
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
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/scope_total.dart';

TextElement _txt(String id, {String? expression}) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
      text: id,
      expression: expression,
    );

/// A fully valid definition: page chrome (static only) + title + one master
/// group + a nested `lines` scope with a single per-row band.
ReportDefinition _valid({
  PageFurniture? furniture,
  ReportBody? body,
}) =>
    ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      furniture: furniture ??
          const PageFurniture(
            pageHeader: Band(
                id: 'furniture/pageHeader',
                type: BandType.pageHeader,
                height: 20),
          ),
      body: body ??
          const ReportBody(
            title: Band(id: 'body/title', type: BandType.title, height: 24),
            root: DetailScope(
              id: 'root',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'root/g0',
                  name: 'invoice',
                  key: r'$F{invoiceNo}',
                  header: Band(
                      id: 'root/g0/header',
                      type: BandType.groupHeader,
                      height: 20),
                  footer: Band(
                      id: 'root/g0/footer',
                      type: BandType.groupFooter,
                      height: 20),
                ),
              ],
              children: <ScopeNode>[
                NestedScope(DetailScope(
                  id: 'root/c0',
                  collectionField: 'lines',
                  children: <ScopeNode>[
                    BandNode(Band(
                        id: 'root/c0/c0', type: BandType.detail, height: 16)),
                  ],
                )),
              ],
            ),
          ),
    );

bool _has(List<Diagnostic> ds, DiagnosticSeverity sev, String needle) =>
    ds.any((Diagnostic d) =>
        d.severity == sev && d.message.toLowerCase().contains(needle));

void main() {
  group('validate', () {
    // #96: the three reserved furniture slots are not laid out, so a band in
    // one is an error. 0004's output promise covers only definitions validate
    // accepts, which keeps implementing them later additive.
    group('reserved furniture slots', () {
      for (final (String slot, PageFurniture furniture)
          in <(String, PageFurniture)>[
        (
          'columnHeader',
          const PageFurniture(
              columnHeader: Band(
                  id: 'f/reserved', type: BandType.columnHeader, height: 10))
        ),
        (
          'columnFooter',
          const PageFurniture(
              columnFooter: Band(
                  id: 'f/reserved', type: BandType.columnFooter, height: 10))
        ),
        (
          'background',
          const PageFurniture(
              background:
                  Band(id: 'f/reserved', type: BandType.background, height: 10))
        ),
      ]) {
        test('a band in the $slot slot is one error naming it', () {
          final List<Diagnostic> ds = validate(_valid(furniture: furniture));
          expect(ds, hasLength(1), reason: '$ds');
          expect(ds.single.severity, DiagnosticSeverity.error);
          expect(ds.single.elementId, 'f/reserved');
          expect(ds.single.message, contains('$slot slot'));
          expect(ds.single.message, contains('reserved'));
        });
      }

      test('a reserved band adds no slot-type or record-field noise', () {
        // Wrong type and a record field: still the one reserved error.
        final List<Diagnostic> ds = validate(_valid(
            furniture: const PageFurniture(
          background: Band(
            id: 'f/bg',
            type: BandType.detail,
            height: 10,
            elements: <ReportElement>[
              TextElement(
                id: 'f/bg/t',
                bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
                text: 't',
                expression: r'$F{customer}',
              ),
            ],
          ),
        )));
        expect(ds, hasLength(1), reason: '$ds');
      });

      test('a reserved band still takes part in duplicate-id checks', () {
        final List<Diagnostic> ds = validate(_valid(
            furniture: const PageFurniture(
          pageHeader: Band(id: 'f/dup', type: BandType.pageHeader, height: 10),
          columnHeader:
              Band(id: 'f/dup', type: BandType.columnHeader, height: 10),
        )));
        expect(_has(ds, DiagnosticSeverity.error, 'duplicate'), isTrue,
            reason: '$ds');
      });
    });

    test('returns empty for a valid definition', () {
      expect(validate(_valid()), isEmpty);
    });

    test('never throws (even on a malformed key)', () {
      expect(
        () => validate(_valid(
            body: const ReportBody(
                root: DetailScope(id: 'root', groups: <GroupLevel>[
          GroupLevel(id: 'g', name: 'n', key: ')('),
        ])))),
        returnsNormally,
      );
    });

    test('I1 flags a duplicate id', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          title: Band(id: 'dup', type: BandType.title, height: 10),
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(id: 'dup', type: BandType.detail, height: 10)),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'duplicate id'),
          isTrue);
    });

    // I2 is retired (#100): a group is keyed by its id, so a repeated name is
    // a label that collides with nothing. A repeated id is I1's.
    test('a duplicate group name within a scope is not an error', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'same', key: '1'),
            GroupLevel(id: 'g2', name: 'same', key: '2'),
          ]),
        ),
      );
      expect(
          validate(def)
              .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
          isEmpty);
    });

    test('I1 flags a duplicate group id', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(id: 'g', name: 'A', key: '1'),
            GroupLevel(id: 'g', name: 'B', key: '2'),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'duplicate id'),
          isTrue);
    });

    test('I3 flags an unparseable group key', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(id: 'g', name: 'n', key: ')('),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'parse'), isTrue);
    });

    // #61: variables were never validated, so a broken one surfaced only as a
    // render-time failure.
    group('I9 variables', () {
      ReportDefinition withVars(List<ReportVariable> vars) =>
          _valid().copyWith(variables: vars);

      test('a valid variable set raises nothing', () {
        expect(
            validate(withVars(const <ReportVariable>[
              ReportVariable(
                  name: 'total',
                  expression: r'$F{amount}',
                  calculation: JetCalculation.sum),
              ReportVariable(
                  name: 'perInvoice',
                  expression: r'$F{amount}',
                  calculation: JetCalculation.sum,
                  resetScope: VariableResetScope.group,
                  resetGroup: 'root/g0'),
            ])),
            isEmpty);
      });

      test('flags an expression that does not parse', () {
        final List<Diagnostic> ds = validate(withVars(const <ReportVariable>[
          ReportVariable(name: 'v', expression: r'$F{amount'),
        ]));
        expect(_has(ds, DiagnosticSeverity.error, 'variable "v"'), isTrue);
        expect(_has(ds, DiagnosticSeverity.error, 'parse'), isTrue);
      });

      test('flags a duplicate name', () {
        expect(
            _has(
                validate(withVars(const <ReportVariable>[
                  ReportVariable(name: 'v', expression: '1'),
                  ReportVariable(name: 'v', expression: '2'),
                ])),
                DiagnosticSeverity.error,
                'duplicate variable name "v"'),
            isTrue);
      });

      test('flags a name in the reserved __ namespace', () {
        expect(
            _has(
                validate(withVars(const <ReportVariable>[
                  ReportVariable(name: '__agg0', expression: '1'),
                ])),
                DiagnosticSeverity.error,
                'reserved'),
            isTrue);
      });

      // #100: a reset names its group by id. A reference that is one group's
      // id and another's name is therefore not ambiguous (#70 flagged it when
      // names were references too), and a reference by name alone is not one.
      test('resolves a group reset by id even when it is another group name',
          () {
        final ReportDefinition def = _valid(
          body: const ReportBody(
            root: DetailScope(id: 'root', groups: <GroupLevel>[
              GroupLevel(id: 'g1', name: 'region', key: '1'),
              GroupLevel(id: 'region', name: 'city', key: '2'),
            ]),
          ),
        ).copyWith(variables: const <ReportVariable>[
          ReportVariable(
              name: 'v',
              expression: '1',
              resetScope: VariableResetScope.group,
              resetGroup: 'region'),
        ]);
        expect(validate(def), isEmpty);
      });

      test('flags a group reset that names a group by its name', () {
        final ReportDefinition def = _valid(
          body: const ReportBody(
            root: DetailScope(id: 'root', groups: <GroupLevel>[
              GroupLevel(id: 'g1', name: 'region', key: '1'),
            ]),
          ),
        ).copyWith(variables: const <ReportVariable>[
          ReportVariable(
              name: 'v',
              expression: '1',
              resetScope: VariableResetScope.group,
              resetGroup: 'region'),
        ]);
        expect(_has(validate(def), DiagnosticSeverity.error, 'not a group id'),
            isTrue);
      });

      test('flags a group reset that names no group', () {
        for (final String? group in <String?>[null, 'nope']) {
          expect(
              _has(
                  validate(withVars(<ReportVariable>[
                    ReportVariable(
                        name: 'v',
                        expression: '1',
                        resetScope: VariableResetScope.group,
                        resetGroup: group),
                  ])),
                  DiagnosticSeverity.error,
                  'resets on group'),
              isTrue,
              reason: 'resetGroup: $group');
        }
      });
    });

    test('I4 flags a field binding on record-blind furniture', () {
      final ReportDefinition def = _valid(
        furniture: PageFurniture(
          pageHeader: Band(
            id: 'furniture/pageHeader',
            type: BandType.pageHeader,
            height: 20,
            elements: <ReportElement>[_txt('f', expression: r'$F{name}')],
          ),
        ),
      );
      final List<Diagnostic> ds = validate(def);
      expect(_has(ds, DiagnosticSeverity.warning, 'field'), isTrue);
    });

    test('I4 flags a field binding on a record-blind title band', () {
      final ReportDefinition def = _valid(
        body: ReportBody(
          title: Band(
            id: 'body/title',
            type: BandType.title,
            height: 20,
            elements: <ReportElement>[_txt('t', expression: r'$F{name}')],
          ),
          root: const DetailScope(id: 'root'),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.warning, 'field'), isTrue);
    });

    // api-friction entry 6: the synthesizer lifts an aggregate wherever it
    // sits in a summary expression, so its operands are not direct bindings
    // there.
    group('I4 in the summary band (an aggregate sink)', () {
      List<Diagnostic> summary(String expression) => validate(_valid(
            body: ReportBody(
              summary: Band(
                id: 'body/summary',
                type: BandType.summary,
                height: 20,
                elements: <ReportElement>[_txt('s', expression: expression)],
              ),
              root: const DetailScope(id: 'root'),
            ),
          ));

      for (final String expression in <String>[
        r'SUM($F{debit})',
        r'SUM($F{debit}) - SUM($F{credit})',
        r'ROUND(AVG($F{rate}), 2)',
        r'COUNT($F{id}) > 0 ? MAX($F{amount}) : 0',
      ]) {
        test('an aggregate operand is not a binding: $expression', () {
          expect(summary(expression), isEmpty);
        });
      }

      test('a field outside every aggregate is still flagged', () {
        final List<Diagnostic> ds = summary(r'SUM($F{debit}) - $F{credit}');
        expect(ds, hasLength(1));
        expect(ds.single.message, contains('field(s) credit,'));
        expect(ds.single.message, isNot(contains('debit')));
      });
    });

    test('I4 still flags a nested aggregate in a band that is no sink', () {
      // Only sinks expand an aggregate; in furniture its operand reads a row
      // that is not there, so the warning is true.
      final ReportDefinition def = _valid(
        furniture: PageFurniture(
          pageHeader: Band(
            id: 'furniture/pageHeader',
            type: BandType.pageHeader,
            height: 20,
            elements: <ReportElement>[
              _txt('f', expression: r'SUM($F{debit}) + 1'),
            ],
          ),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.warning, 'field'), isTrue);
    });

    test('I5 flags a band whose type is inconsistent with its slot', () {
      final ReportDefinition def = _valid(
        furniture: const PageFurniture(
          pageHeader: Band(
              id: 'furniture/pageHeader', type: BandType.detail, height: 20),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'type'), isTrue);
    });

    test('I6 flags a nested scope missing its collectionField', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(id: 'root/c0')),
          ]),
        ),
      );
      expect(
          _has(validate(def), DiagnosticSeverity.error, 'collection'), isTrue);
    });

    test('I6 flags a root scope that carries a collectionField', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', collectionField: 'oops'),
        ),
      );
      expect(
          _has(validate(def), DiagnosticSeverity.error, 'collection'), isTrue);
    });

    test('an inline aggregate outside summary/group-footer is an error', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: 16,
              elements: <ReportElement>[
                TextElement(
                  id: 'bad',
                  bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                  text: 'bad',
                  expression: r'SUM($F{amount})',
                ),
              ],
            )),
          ]),
        ),
      );
      final errors = validate(def)
          .where((d) => d.severity == DiagnosticSeverity.error)
          .map((d) => d.message);
      expect(errors, anyElement(contains('aggregate')));
    });

    test('an inline aggregate in summary is valid (no aggregate diagnostic)',
        () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          summary: Band(
            id: 's',
            type: BandType.summary,
            height: 16,
            elements: <ReportElement>[
              TextElement(
                id: 'ok',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                text: 'ok',
                expression: r'SUM($F{amount})',
              ),
            ],
          ),
          root: const DetailScope(id: 'root'),
        ),
      );
      expect(
          validate(def).where((d) => d.message.contains('aggregate')), isEmpty);
      // The aggregate's operand field is folded over data rows, so the
      // record-blind summary is NOT flagged for referencing it: clean overall.
      expect(validate(def), isEmpty,
          reason: 'a summary inline aggregate validates completely clean');
    });

    test(
        'an inline aggregate in a group FOOTER is valid, but in a group HEADER '
        'is an error', () {
      Band band(String id, BandType type) => Band(
            id: id,
            type: type,
            height: 16,
            elements: <ReportElement>[
              TextElement(
                id: '$id.el',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                text: id,
                expression: r'SUM($F{amount})',
              ),
            ],
          );
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(
              id: 'g',
              name: 'g',
              key: r'$F{k}',
              header: band('gh', BandType.groupHeader),
              footer: band('gf', BandType.groupFooter),
            ),
          ]),
        ),
      );
      final aggErrors = validate(def)
          .where((d) => d.severity == DiagnosticSeverity.error)
          .where((d) => d.message.contains('aggregate'))
          .toList();
      expect(aggErrors, hasLength(1),
          reason: 'header aggregate flagged, footer aggregate allowed');
      expect(aggErrors.single.elementId, 'gh.el');
    });

    test('an inline aggregate in a NESTED-scope group footer is an error', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'ng',
                  name: 'ng',
                  key: r'$F{k}',
                  footer: Band(
                    id: 'nf',
                    type: BandType.groupFooter,
                    height: 16,
                    elements: <ReportElement>[
                      TextElement(
                        id: 'nf.el',
                        bounds:
                            const JetRect(x: 0, y: 0, width: 100, height: 16),
                        text: 'nf',
                        expression: r'SUM($F{amount})',
                      ),
                    ],
                  ),
                ),
              ],
            )),
          ]),
        ),
      );
      final aggErrors = validate(def)
          .where((d) => d.severity == DiagnosticSeverity.error)
          .where((d) => d.message.contains('aggregate'))
          .toList();
      expect(aggErrors, hasLength(1),
          reason:
              'a non-root (nested-scope) group footer is not an aggregate sink');
      expect(aggErrors.single.elementId, 'nf.el');
    });

    test('a footer on the ROOT scope is an error', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
            root: DetailScope(
                id: 'root',
                footer:
                    Band(id: 'rf', type: BandType.groupFooter, height: 12))),
      );
      expect(
        validate(def)
            .where((d) => d.severity == DiagnosticSeverity.error)
            .map((d) => d.message),
        anyElement(contains('footer')),
      );
    });

    test('an inline aggregate in a NESTED-scope footer is valid (a sink)', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              footer: Band(
                  id: 'lf',
                  type: BandType.groupFooter,
                  height: 12,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'ot',
                      bounds: const JetRect(x: 0, y: 0, width: 100, height: 12),
                      text: 'ot',
                      expression: r'SUM($F{lineTotal})',
                    ),
                  ]))),
        ])),
      );
      expect(
          validate(def).where((d) => d.message.contains('aggregate')), isEmpty,
          reason: 'a nested-scope footer is an aggregate sink in B1');
    });

    test('a nested scope without a footer emits no footer diagnostic', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(id: 'l', type: BandType.detail, height: 12)),
                ])),
          ])));
      expect(validate(def).where((d) => d.message.contains('footer')), isEmpty);
    });

    test('a nested footer with the wrong band type is a slot error', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              footer: Band(id: 'lf', type: BandType.detail, height: 12))),
        ])),
      );
      expect(
        validate(def)
            .where((d) => d.severity == DiagnosticSeverity.error)
            .map((d) => d.message),
        anyElement(contains('groupFooter')),
      );
    });

    test('totals on the ROOT scope is an error', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
              root: DetailScope(
                  id: 'root',
                  totals: const <ScopeTotal>[ScopeTotal('x', r'SUM($F{a})')])));
      expect(
          validate(def)
              .where((d) => d.severity == DiagnosticSeverity.error)
              .map((d) => d.message),
          anyElement(contains('root')));
    });

    test('a published total on a nested scope is valid', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                totals: const <ScopeTotal>[
                  ScopeTotal('orderTotal', r'SUM($F{lineTotal})')
                ])),
          ])));
      expect(validate(def).where((d) => d.severity == DiagnosticSeverity.error),
          isEmpty);
    });

    test('a non-aggregate published total is an error', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                totals: const <ScopeTotal>[ScopeTotal('t', r'$F{x} + 1')])),
          ])));
      expect(
          validate(def)
              .where((d) => d.severity == DiagnosticSeverity.error)
              .map((d) => d.message),
          anyElement(contains('aggregate')));
    });

    test('duplicate published-total names in one scope is an error', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                totals: const <ScopeTotal>[
                  ScopeTotal('t', r'SUM($F{a})'),
                  ScopeTotal('t', r'SUM($F{b})')
                ])),
          ])));
      expect(
          validate(def)
              .where((d) => d.severity == DiagnosticSeverity.error)
              .map((d) => d.message),
          anyElement(contains('duplicate')));
    });

    test('an unknown scope node is an info diagnostic naming its kind', () {
      final def = ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: const ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            UnknownScopeNode(rawJson: <String, Object?>{'kind': 'futureBlock'}),
          ])));
      expect(
          validate(def)
              .where((d) => d.severity == DiagnosticSeverity.info)
              .map((d) => d.message),
          anyElement(allOf(contains('futureBlock'), contains('not rendered'))));
    });
  });
}
