// The `RenderOptions.knownFields` default (#99).
//
// Left null, it is derived from the data source when the source declares an
// explicit schema: `JetObjectDataSource` and `JetPagedDataSource` always do,
// `JetInMemoryDataSource` and `JetJsonDataSource` when `fields:` is passed. A
// binding to a field outside that schema then renders `#ERROR` instead of an
// empty cell. An inferred schema, or a custom source, still renders it empty:
// inference cannot tell a typo from an optional key absent from this batch.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;

const PageFormat _page =
    PageFormat(width: 400, height: 200, margins: JetEdgeInsets.all(10));

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('name', type: JetFieldType.string),
];

ReportDefinition _flat(String expression) => ReportDefinition(
      name: 'known fields',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 24,
              elements: <ReportElement>[
                TextElement(
                  id: 'value',
                  bounds: const JetRect(x: 0, y: 0, width: 360, height: 18),
                  text: 'value',
                  expression: expression,
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The text of every `value` element in [report], in page order.
List<String> _values(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final FramePrimitive p in report.pageAt(i).frame.primitives)
          if (p is TextRunPrimitive && p.elementId == 'value')
            p.lines.map((TextLine l) => l.text).join(),
    ];

List<String> _render(
  JetDataSource source, {
  String expression = r'$F{nmae}',
  RenderOptions options = const RenderOptions(),
}) =>
    _values(const JetReportEngine()
        .renderDefinition(_flat(expression), source, options: options));

class _CustomSource implements JetDataSource {
  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      JetInMemoryDataSource(
        const <Map<String, Object?>>[
          <String, Object?>{'name': 'Ada'},
        ],
        fields: _schema,
      ).open(params);
}

void main() {
  const List<Map<String, Object?>> rows = <Map<String, Object?>>[
    <String, Object?>{'name': 'Ada'},
  ];

  group('an explicit schema makes an unknown field #ERROR by default', () {
    test('in-memory source with fields', () {
      expect(_render(JetInMemoryDataSource(rows, fields: _schema)),
          <String>['#ERROR']);
    });

    test('JSON source with fields', () {
      expect(
          _render(JetJsonDataSource.parse('[{"name":"Ada"}]', fields: _schema)),
          <String>['#ERROR']);
    });

    test('object source', () {
      expect(
          _render(JetObjectDataSource<String>(
            const <String>['Ada'],
            fields: _schema,
            row: (String n) => <String, Object?>{'name': n},
          )),
          <String>['#ERROR']);
    });

    test('paged source', () {
      expect(
          _render(JetPagedDataSource(
            fields: _schema,
            pageSize: 10,
            fetchPage: (int page) =>
                page == 0 ? rows : const <Map<String, Object?>>[],
          )),
          <String>['#ERROR']);
    });

    test('a known field still resolves', () {
      expect(
          _render(JetInMemoryDataSource(rows, fields: _schema),
              expression: r'$F{name}'),
          <String>['Ada']);
    });

    test('the unresolved token option applies to the derived set', () {
      expect(
          _render(JetInMemoryDataSource(rows, fields: _schema),
              options: const RenderOptions(unresolvedFieldToken: '??')),
          <String>['??']);
    });
  });

  group('without an explicit schema the binding renders empty, as before', () {
    test('in-memory source with an inferred schema', () {
      expect(_render(JetInMemoryDataSource(rows)), <String>['']);
    });

    test('JSON source with an inferred schema', () {
      expect(
          _render(JetJsonDataSource.parse('[{"name":"Ada"}]')), <String>['']);
    });

    test('a custom source', () {
      expect(_render(_CustomSource()), <String>['']);
    });
  });

  test('a host-supplied knownFields wins over the derived set', () {
    expect(
        _render(JetInMemoryDataSource(rows, fields: _schema),
            options:
                const RenderOptions(knownFields: <String>{'name', 'nmae'})),
        <String>[''],
        reason:
            'the host declared nmae, so it resolves (empty) without #ERROR');
  });

  test('nested collection fields are part of the derived set', () {
    final ReportDefinition def = ReportDefinition(
      name: 'nested',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'line',
                  type: BandType.detail,
                  height: 24,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'value',
                      bounds: const JetRect(x: 0, y: 0, width: 360, height: 18),
                      text: 'value',
                      expression: r'$F{sku}',
                    ),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );
    final JetInMemoryDataSource source = JetInMemoryDataSource(
      const <Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'sku': 'A-1'},
          ],
        },
      ],
      fields: const <FieldDef>[
        FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('sku', type: JetFieldType.string),
        ]),
      ],
    );
    expect(_values(const JetReportEngine().renderDefinition(def, source)),
        <String>['A-1']);
  });
}
