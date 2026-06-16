// JetReportEngine facade (011 — contracts C1/C3): fill resolves tokens to
// values, parameters thread through, pagination repeats chrome with a correct
// page count, and rendering is deterministic.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/value_type.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// 200x100 page, 10pt margins -> 80pt printable height. With 20pt page
// header + footer, body capacity is 40pt.
const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

TextElement _text(String id, String expression, {double y = 0}) => TextElement(
      id: id,
      bounds: JetRect(x: 0, y: y, width: 180, height: 16),
      text: id,
      expression: expression,
    );

/// All rendered text across [frame], element id -> joined run text.
Map<String, String> _texts(PageFrame frame) => <String, String>{
      for (final TextRunPrimitive p
          in frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId != null)
          p.elementId!: p.lines.map((TextLine l) => l.text).join(),
    };

/// Every rendered text run on every page of [report].
List<String> _allRuns(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  group('C1 — fill resolves tokens to values', () {
    final ReportDefinition template = ReportDefinition(
      name: 'flat',
      page: _smallPage,
      parameters: const <ReportParameter>[
        ReportParameter(name: 'printedBy', type: JetFieldType.string),
      ],
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 20,
          elements: <ReportElement>[_text('by', r'$P{printedBy}')],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 20,
              elements: <ReportElement>[_text('name', r'$F{name}')],
            )),
          ],
        ),
      ),
    );
    final JetInMemoryDataSource source =
        JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'name': 'alpha'},
      <String, Object?>{'name': 'beta'},
      <String, Object?>{'name': 'gamma'},
    ]);

    test('every bound element shows its evaluated value — zero tokens', () {
      final RenderedReport report = const JetReportEngine().renderDefinition(
        template,
        source,
        options: const RenderOptions(
            parameters: <String, Object?>{'printedBy': 'A. Urel'}),
      );
      final List<String> runs = _allRuns(report);
      expect(runs, containsAll(<String>['alpha', 'beta', 'gamma']));
      for (final String run in runs) {
        expect(run, isNot(contains(r'$F{')));
        expect(run, isNot(contains(r'$P{')));
        expect(run, isNot(contains(r'$V{')));
      }
    });

    test('a parameter-bound element shows the supplied value', () {
      final RenderedReport report = const JetReportEngine().renderDefinition(
        template,
        source,
        options: const RenderOptions(
            parameters: <String, Object?>{'printedBy': 'A. Urel'}),
      );
      expect(_allRuns(report), contains('A. Urel'));
    });
  });

  group('C3 — pagination with repeated chrome', () {
    final ReportDefinition template = ReportDefinition(
      name: 'paged',
      page: _smallPage,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[_text('hd', r'"HEADER"')],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            _text('pf', r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
          ],
        ),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 30,
              elements: <ReportElement>[_text('name', r'$F{name}')],
            )),
          ],
        ),
      ),
    );
    // Body capacity 40pt and 30pt bands -> exactly one row per page.
    final JetInMemoryDataSource source =
        JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < 5; i++) <String, Object?>{'name': 'row $i'},
    ]);

    test('content splits at band boundaries with a correct page count', () {
      final RenderedReport report =
          const JetReportEngine().renderDefinition(template, source);
      expect(report.pageCount, 5);
      for (int i = 0; i < 5; i++) {
        expect(_texts(report.pageAt(i).frame)['name'], 'row $i');
      }
    });

    test('page header/footer repeat on every page; PAGE_X/COUNT resolve', () {
      final RenderedReport report =
          const JetReportEngine().renderDefinition(template, source);
      for (int i = 0; i < report.pageCount; i++) {
        final Map<String, String> texts = _texts(report.pageAt(i).frame);
        expect(texts['hd'], 'HEADER');
        expect(texts['pf'], 'Page ${i + 1} of 5');
      }
    });
  });

  group('C2 — master/detail + aggregates (US2)', () {
    // A tall page so the whole invoice fits one page (pagination is C3's job).
    const PageFormat tallPage =
        PageFormat(width: 400, height: 800, margins: JetEdgeInsets.all(10));

    // Master fields live in master-scope DETAIL bands (no collectionField):
    // title/summary have no row context by design (007b §5 — $F{} blanks
    // there), and per-invoice header/total bands repeat correctly for
    // multi-invoice datasets.
    ReportDefinition invoiceTemplate() => const ReportDefinition(
          name: 'invoice',
          page: tallPage,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'root/c0',
                  type: BandType.detail,
                  height: 20,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'invoiceNo',
                      bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                      text: 'invoiceNo',
                      expression: r'$F{invoiceNo}',
                    ),
                  ],
                )),
                NestedScope(DetailScope(
                  id: 'root/c1',
                  collectionField: 'lines',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'root/c1/c0',
                      type: BandType.detail,
                      height: 20,
                      elements: <ReportElement>[
                        TextElement(
                          id: 'desc',
                          bounds: JetRect(x: 0, y: 0, width: 150, height: 16),
                          text: 'desc',
                          expression: r'$F{desc}',
                        ),
                        TextElement(
                          id: 'lineTotal',
                          bounds: JetRect(x: 160, y: 0, width: 100, height: 16),
                          text: 'lineTotal',
                          expression: r'$F{qty} * $F{price}',
                        ),
                      ],
                    )),
                  ],
                )),
                BandNode(Band(
                  id: 'root/c2',
                  type: BandType.detail,
                  height: 20,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'total',
                      bounds: JetRect(x: 160, y: 0, width: 100, height: 16),
                      text: 'total',
                      expression: r'$F{total}',
                    ),
                  ],
                )),
              ],
            ),
          ),
        );

    JetInMemoryDataSource invoiceSource() =>
        JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{
            'invoiceNo': 'INV-1042',
            'total': 19.5,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'desc': 'Widget', 'qty': 2, 'price': 3.0},
              <String, Object?>{'desc': 'Gadget', 'qty': 1, 'price': 12.5},
              <String, Object?>{'desc': 'Gizmo', 'qty': 4, 'price': 0.25},
            ],
          },
        ]);

    List<String> runsFor(RenderedReport report, String id) => <String>[
          for (int i = 0; i < report.pageCount; i++)
            for (final TextRunPrimitive p in report
                .pageAt(i)
                .frame
                .primitives
                .whereType<TextRunPrimitive>())
              if (p.elementId == id) p.lines.map((TextLine l) => l.text).join(),
        ];

    test(
        'a collection-bound band repeats once per child record with child '
        'values resolved', () {
      final RenderedReport report = const JetReportEngine()
          .renderDefinition(invoiceTemplate(), invoiceSource());
      expect(runsFor(report, 'invoiceNo'), <String>['INV-1042']);
      expect(runsFor(report, 'desc'), <String>['Widget', 'Gadget', 'Gizmo']);
      expect(runsFor(report, 'lineTotal'), <String>['6.0', '12.5', '1.0'],
          reason: 'the line-total expression computes per child row');
    });

    test('the invoice total equals the exact sum of line amounts (SC-002)', () {
      final RenderedReport report = const JetReportEngine()
          .renderDefinition(invoiceTemplate(), invoiceSource());
      final double linesSum = runsFor(report, 'lineTotal')
          .map(double.parse)
          .fold(0, (double a, double b) => a + b);
      expect(double.parse(runsFor(report, 'total').single), linesSum);
    });

    test('nested collections iterate at arbitrary depth, in document order',
        () {
      final ReportDefinition template = const ReportDefinition(
        name: 'nested',
        page: tallPage,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'root/c0',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(
                    id: 'root/c0/c0',
                    type: BandType.detail,
                    height: 20,
                    elements: <ReportElement>[
                      TextElement(
                        id: 'line',
                        bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                        text: 'line',
                        expression: r'$F{name}',
                      ),
                    ],
                  )),
                  NestedScope(DetailScope(
                    id: 'root/c0/c1',
                    collectionField: 'subs',
                    children: <ScopeNode>[
                      BandNode(Band(
                        id: 'root/c0/c1/c0',
                        type: BandType.detail,
                        height: 16,
                        elements: <ReportElement>[
                          TextElement(
                            id: 'sub',
                            bounds:
                                JetRect(x: 20, y: 0, width: 200, height: 14),
                            text: 'sub',
                            expression: r'$F{label}',
                          ),
                        ],
                      )),
                    ],
                  )),
                ],
              )),
            ],
          ),
        ),
      );
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'L1',
              'subs': <Map<String, Object?>>[
                <String, Object?>{'label': 'L1.a'},
                <String, Object?>{'label': 'L1.b'},
              ],
            },
            <String, Object?>{
              'name': 'L2',
              'subs': <Map<String, Object?>>[
                <String, Object?>{'label': 'L2.a'},
              ],
            },
          ],
        },
      ]);
      final RenderedReport report =
          const JetReportEngine().renderDefinition(template, source);
      expect(runsFor(report, 'line'), <String>['L1', 'L2']);
      expect(runsFor(report, 'sub'), <String>['L1.a', 'L1.b', 'L2.a']);
      // Document order: each line is followed by its own sub-rows.
      final List<String> ordered = <String>[
        for (final TextRunPrimitive p
            in report.pageAt(0).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == 'line' || p.elementId == 'sub')
            p.lines.map((TextLine l) => l.text).join(),
      ];
      expect(ordered, <String>['L1', 'L1.a', 'L1.b', 'L2', 'L2.a']);
    });

    test('a nested-scope footer sums its collection and resets per parent', () {
      final def = ReportDefinition(
          name: 'nestedFooter',
          page: tallPage,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                footer: Band(
                    id: 'lf',
                    type: BandType.groupFooter,
                    height: 16,
                    elements: <ReportElement>[
                      TextElement(
                          id: 'ot',
                          bounds:
                              const JetRect(x: 0, y: 0, width: 100, height: 14),
                          text: 'ot',
                          expression: r'SUM($F{lineTotal})')
                    ]),
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'l',
                      type: BandType.detail,
                      height: 16,
                      elements: <ReportElement>[
                        TextElement(
                            id: 'lt',
                            bounds: const JetRect(
                                x: 0, y: 0, width: 100, height: 14),
                            text: 'lt',
                            expression: r'$F{lineTotal}')
                      ])),
                ])),
          ])));
      final source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'lineTotal': 10},
            <String, Object?>{'lineTotal': 20}
          ]
        },
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'lineTotal': 5}
          ]
        },
      ]);
      final report = const JetReportEngine().renderDefinition(def, source);
      expect(runsFor(report, 'ot'), <String>['30.0', '5.0'],
          reason: 'the footer sums each parent\'s lines and resets per parent');
    });

    test('an empty nested collection emits no footer', () {
      final def = ReportDefinition(
          name: 'emptyNested',
          page: tallPage,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                footer: Band(
                    id: 'lf',
                    type: BandType.groupFooter,
                    height: 16,
                    elements: <ReportElement>[
                      TextElement(
                          id: 'ot',
                          bounds:
                              const JetRect(x: 0, y: 0, width: 100, height: 14),
                          text: 'ot',
                          expression: r'SUM($F{lineTotal})')
                    ]),
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'l',
                      type: BandType.detail,
                      height: 16,
                      elements: <ReportElement>[
                        TextElement(
                            id: 'lt',
                            bounds: const JetRect(
                                x: 0, y: 0, width: 100, height: 14),
                            text: 'lt',
                            expression: r'$F{lineTotal}')
                      ])),
                ])),
          ])));
      final source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'lines': <Map<String, Object?>>[]},
      ]);
      final report = const JetReportEngine().renderDefinition(def, source);
      expect(runsFor(report, 'ot'), isEmpty, reason: 'no rows → no footer');
    });

    test('a nested footer with an expression argument folds the product', () {
      final def = ReportDefinition(
          name: 'exprArg',
          page: tallPage,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                footer: Band(
                    id: 'lf',
                    type: BandType.groupFooter,
                    height: 16,
                    elements: <ReportElement>[
                      TextElement(
                          id: 'ot',
                          bounds:
                              const JetRect(x: 0, y: 0, width: 100, height: 14),
                          text: 'ot',
                          expression: r'SUM($F{qty} * $F{price})')
                    ]),
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'l',
                      type: BandType.detail,
                      height: 16,
                      elements: <ReportElement>[
                        TextElement(
                            id: 'lt',
                            bounds: const JetRect(
                                x: 0, y: 0, width: 100, height: 14),
                            text: 'lt',
                            expression: r'$F{qty}')
                      ])),
                ])),
          ])));
      final source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'qty': 2, 'price': 3.0},
            <String, Object?>{'qty': 4, 'price': 0.5}
          ]
        },
      ]);
      final report = const JetReportEngine().renderDefinition(def, source);
      expect(runsFor(report, 'ot'), <String>['8.0'], reason: '2*3 + 4*0.5 = 8');
    });

    test('a nested footer can show a parent field alongside its aggregate', () {
      final def = ReportDefinition(
          name: 'footerParentField',
          page: tallPage,
          body: ReportBody(
              root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                footer: Band(
                    id: 'lf',
                    type: BandType.groupFooter,
                    height: 16,
                    elements: <ReportElement>[
                      TextElement(
                          id: 'who',
                          bounds:
                              const JetRect(x: 0, y: 0, width: 100, height: 14),
                          text: 'who',
                          expression: r'$F{orderNo}'),
                      TextElement(
                          id: 'ot',
                          bounds: const JetRect(
                              x: 110, y: 0, width: 100, height: 14),
                          text: 'ot',
                          expression: r'SUM($F{lineTotal})'),
                    ]),
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'l',
                      type: BandType.detail,
                      height: 16,
                      elements: <ReportElement>[
                        TextElement(
                            id: 'lt',
                            bounds: const JetRect(
                                x: 0, y: 0, width: 100, height: 14),
                            text: 'lt',
                            expression: r'$F{lineTotal}')
                      ])),
                ])),
          ])));
      final source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'orderNo': 'A',
          'lines': <Map<String, Object?>>[
            <String, Object?>{'lineTotal': 10},
            <String, Object?>{'lineTotal': 20}
          ]
        },
      ]);
      final report = const JetReportEngine().renderDefinition(def, source);
      expect(runsFor(report, 'who'), <String>['A'],
          reason: 'the footer resolves the parent (order) row field');
      expect(runsFor(report, 'ot'), <String>['30.0']);
    });

    test(
        'a sum variable computes at its reset scope: group subtotal + grand '
        'total; group header/footer render at key boundaries', () {
      final ReportDefinition template = const ReportDefinition(
        name: 'groups',
        page: tallPage,
        variables: <ReportVariable>[
          ReportVariable(
            name: 'subtotal',
            expression: r'$F{amount}',
            calculation: JetCalculation.sum,
            resetScope: VariableResetScope.group,
            resetGroup: 'byCategory',
          ),
          ReportVariable(
            name: 'grandTotal',
            expression: r'$F{amount}',
            calculation: JetCalculation.sum,
          ),
        ],
        body: ReportBody(
          summary: Band(
            id: 'body/summary',
            type: BandType.summary,
            height: 18,
            elements: <ReportElement>[
              TextElement(
                id: 'grand',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                text: 'grand',
                expression: r'$V{grandTotal}',
              ),
            ],
          ),
          root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[
              GroupLevel(
                id: 'byCategory',
                name: 'byCategory',
                key: r'$F{category}',
                header: Band(
                  id: 'root/g0/header',
                  type: BandType.groupHeader,
                  height: 18,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'cat',
                      bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                      text: 'cat',
                      expression: r'$F{category}',
                    ),
                  ],
                ),
                footer: Band(
                  id: 'root/g0/footer',
                  type: BandType.groupFooter,
                  height: 18,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'subtotal',
                      bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                      text: 'subtotal',
                      expression: r'$V{subtotal}',
                    ),
                  ],
                ),
              ),
            ],
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 18,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amount',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                    text: 'amount',
                    expression: r'$F{amount}',
                  ),
                ],
              )),
            ],
          ),
        ),
      );
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'category': 'A', 'amount': 10},
        <String, Object?>{'category': 'A', 'amount': 20},
        <String, Object?>{'category': 'B', 'amount': 5},
      ]);
      final RenderedReport report =
          const JetReportEngine().renderDefinition(template, source);
      expect(runsFor(report, 'cat'), <String>['A', 'B'],
          reason: 'one group header per key boundary');
      expect(runsFor(report, 'subtotal'), <String>['30.0', '5.0'],
          reason: 'the sum resets at the group boundary');
      expect(runsFor(report, 'grand'), <String>['35.0'],
          reason: 'the grand total spans the whole report');
    });

    test('an inline summary aggregate renders the same as a hand variable', () {
      final ReportDefinition inline = ReportDefinition(
        name: 'inline',
        page: tallPage,
        body: ReportBody(
          summary: Band(
            id: 'body/summary',
            type: BandType.summary,
            height: 18,
            elements: <ReportElement>[
              TextElement(
                id: 'grand',
                bounds: const JetRect(x: 0, y: 0, width: 200, height: 16),
                text: 'grand',
                expression: r'SUM($F{amount})',
              ),
            ],
          ),
          root: const DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 18,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amount',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                    text: 'amount',
                    expression: r'$F{amount}',
                  ),
                ],
              )),
            ],
          ),
        ),
      );
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 10},
        <String, Object?>{'amount': 20},
        <String, Object?>{'amount': 5},
      ]);
      final RenderedReport report =
          const JetReportEngine().renderDefinition(inline, source);
      expect(runsFor(report, 'grand'), <String>['35.0'],
          reason: 'the inline SUM folds over all master rows at report scope');
    });

    test('an inline group-footer aggregate matches a group-scoped variable',
        () {
      final ReportDefinition inline = ReportDefinition(
        name: 'inlineGroup',
        page: tallPage,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[
              GroupLevel(
                id: 'byCategory',
                name: 'byCategory',
                key: r'$F{category}',
                footer: Band(
                  id: 'root/g0/footer',
                  type: BandType.groupFooter,
                  height: 18,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'subtotal',
                      bounds: const JetRect(x: 0, y: 0, width: 200, height: 16),
                      text: 'subtotal',
                      expression: r'SUM($F{amount})',
                    ),
                  ],
                ),
              ),
            ],
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 18,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amount',
                    bounds: const JetRect(x: 0, y: 0, width: 200, height: 16),
                    text: 'amount',
                    expression: r'$F{amount}',
                  ),
                ],
              )),
            ],
          ),
        ),
      );
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'category': 'A', 'amount': 10},
        <String, Object?>{'category': 'A', 'amount': 20},
        <String, Object?>{'category': 'B', 'amount': 5},
      ]);
      final RenderedReport report =
          const JetReportEngine().renderDefinition(inline, source);
      expect(runsFor(report, 'subtotal'), <String>['30.0', '5.0'],
          reason:
              'the inline SUM resets at the group boundary like a group variable');
    });
  });

  group('determinism (FR-010 / SC-004)', () {
    test('identical inputs render byte-identical pages', () {
      final ReportDefinition template = ReportDefinition(
        name: 'det',
        page: _smallPage,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  _text('v', r'FORMAT($F{amount}, "#,##0.00")'),
                ],
              )),
            ],
          ),
        ),
      );
      JetInMemoryDataSource source() =>
          JetInMemoryDataSource(<Map<String, Object?>>[
            for (int i = 0; i < 5; i++) <String, Object?>{'amount': i * 11.3},
          ]);
      const RenderOptions options = RenderOptions(locale: Locale('de'));
      final RenderedReport a = const JetReportEngine()
          .renderDefinition(template, source(), options: options);
      final RenderedReport b = const JetReportEngine()
          .renderDefinition(template, source(), options: options);
      expect(a.pageCount, b.pageCount);
      for (int i = 0; i < a.pageCount; i++) {
        expect(a.pageAt(i).frame, b.pageAt(i).frame,
            reason: 'page $i must be byte-identical across renders');
      }
    });
  });
}
