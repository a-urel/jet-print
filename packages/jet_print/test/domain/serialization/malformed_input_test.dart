// Malformed report JSON fails with ReportFormatException — and only that.
//
// Regression (#60): decoding promised ReportFormatException, but `!`/`as` casts,
// `values.byName` lookups and unwrapped sub-codecs let a TypeError, an
// ArgumentError or a FormatException through, so a host catching
// `on ReportFormatException` crashed on a truncated or hand-edited file.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A definition that touches every decoder: parameters, variables, furniture,
/// title, groups, a nested scope with totals and footer, a crosstab, and one
/// element of each built-in type.
ReportDefinition _everything() {
  const JetRect r = JetRect(x: 0, y: 0, width: 80, height: 16);
  return ReportDefinition(
    name: 'Everything',
    page: PageFormat.a4Portrait,
    parameters: const <ReportParameter>[
      ReportParameter(name: 'asOf', type: JetFieldType.dateTime),
    ],
    variables: const <ReportVariable>[
      ReportVariable(
        name: 'sum',
        expression: r'$F{amount}',
        calculation: JetCalculation.sum,
        resetScope: VariableResetScope.group,
        resetGroup: 'root/g0',
      ),
    ],
    furniture: const PageFurniture(
      pageHeader: Band(
          id: 'ph',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[
            TextElement(id: 'pn', bounds: r, text: '', expression: '1'),
          ]),
    ),
    body: ReportBody(
      title: const Band(id: 'title', type: BandType.title, height: 20),
      root: DetailScope(
        id: 'root',
        groups: const <GroupLevel>[
          GroupLevel(
            id: 'root/g0',
            name: 'invoice',
            key: r'$F{invoiceNo}',
            header: Band(id: 'gh', type: BandType.groupHeader, height: 20),
          ),
        ],
        children: <ScopeNode>[
          BandNode(Band(
            id: 'detail',
            type: BandType.detail,
            height: 120,
            elements: <ReportElement>[
              const TextElement(
                  id: 't', bounds: r, text: 'a', format: '#,##0', name: 'T'),
              const ShapeElement(id: 's', bounds: r, kind: ShapeKind.ellipse),
              const ImageElement(
                  id: 'i', bounds: r, source: FieldImageSource('photo')),
              const BarcodeElement(
                  id: 'b',
                  bounds: r,
                  symbology: BarcodeSymbology.code128,
                  data: '123'),
              const ChartElement(
                  id: 'c',
                  bounds: r,
                  chartType: ChartType.pie,
                  collectionField: 'months',
                  valueExpression: r'$F{v}',
                  title: 'C'),
            ],
          )),
          const NestedScope(DetailScope(
            id: 'lines',
            collectionField: 'lines',
            totals: <ScopeTotal>[ScopeTotal('lineSum', r'SUM($F{qty})')],
            footer: Band(id: 'lf', type: BandType.groupFooter, height: 12),
            children: <ScopeNode>[
              BandNode(Band(id: 'ld', type: BandType.detail, height: 12)),
            ],
          )),
          const CrosstabNode(Crosstab(
            id: 'ct',
            rowGroups: <CrosstabGroup>[
              CrosstabGroup(id: 'ct/r', name: 'R', expression: r'$F{region}'),
            ],
            columnGroups: <CrosstabGroup>[
              CrosstabGroup(id: 'ct/c', name: 'C', expression: r'$F{q}'),
            ],
            measures: <CrosstabMeasure>[
              CrosstabMeasure(
                  id: 'ct/m',
                  name: 'M',
                  expression: r'$F{amount}',
                  aggregate: JetCalculation.sum),
            ],
          )),
        ],
      ),
    ),
  );
}

Map<String, Object?> _encoded() =>
    (jsonDecode(JetReportFormat.encodeDefinitionJson(_everything())) as Map)
        .cast<String, Object?>();

/// Every path to a value inside [node], as a list of map keys / list indices.
Iterable<List<Object>> _paths(Object? node,
    [List<Object> at = const <Object>[]]) sync* {
  if (node is Map) {
    for (final Object? k in node.keys) {
      final List<Object> p = <Object>[...at, k! as String];
      yield p;
      yield* _paths(node[k], p);
    }
  } else if (node is List) {
    for (int i = 0; i < node.length; i++) {
      final List<Object> p = <Object>[...at, i];
      yield p;
      yield* _paths(node[i], p);
    }
  }
}

/// A deep copy of [root] with the value at [path] replaced by [value], or
/// removed when [remove] is set.
Map<String, Object?> _mutate(Map<String, Object?> root, List<Object> path,
    {Object? value, bool remove = false}) {
  final Map<String, Object?> copy =
      (jsonDecode(jsonEncode(root)) as Map).cast<String, Object?>();
  Object? parent = copy;
  for (final Object step in path.take(path.length - 1)) {
    parent = parent is Map ? parent[step] : (parent! as List)[step as int];
  }
  final Object last = path.last;
  if (parent is Map) {
    remove ? parent.remove(last) : parent[last] = value;
  } else {
    remove
        ? (parent! as List).removeAt(last as int)
        : (parent! as List)[last as int] = value;
  }
  return copy;
}

Matcher get _reportFormatError => throwsA(isA<ReportFormatException>());

void main() {
  test('the fixture round-trips, so every mutation below starts valid', () {
    expect(JetReportFormat.decodeDefinition(_encoded()), _everything());
  });

  group('the cases from #60', () {
    test('an empty root scope', () {
      final Map<String, Object?> json = _encoded();
      (json['body']! as Map)['root'] = <String, Object?>{};
      expect(() => JetReportFormat.decodeDefinition(json), _reportFormatError);
    });

    test('an unknown variable calculation', () {
      final Map<String, Object?> json = _encoded();
      ((json['variables']! as List).single as Map)['calculation'] = 'median';
      expect(() => JetReportFormat.decodeDefinition(json), _reportFormatError);
    });

    test('an unknown parameter type', () {
      final Map<String, Object?> json = _encoded();
      ((json['parameters']! as List).single as Map)['type'] = 'uuid';
      expect(() => JetReportFormat.decodeDefinition(json), _reportFormatError);
    });

    test('text that is not JSON', () {
      expect(() => JetReportFormat.decodeDefinitionJson('{"name": '),
          _reportFormatError);
    });

    test('the exception keeps the underlying cause in its message', () {
      final Map<String, Object?> json = _encoded();
      ((json['variables']! as List).single as Map)['calculation'] = 'median';
      expect(
          () => JetReportFormat.decodeDefinition(json),
          throwsA(isA<ReportFormatException>().having(
              (ReportFormatException e) => e.message,
              'message',
              contains('median'))));
    });
  });

  // Every value in the document swapped for each wrong-typed stand-in, and
  // every key removed: decoding must either succeed (a tolerant default) or
  // throw ReportFormatException — never any other type.
  test('no malformed shape escapes as anything but ReportFormatException', () {
    final Map<String, Object?> base = _encoded();
    const List<Object?> standIns = <Object?>[
      null,
      42,
      'x',
      true,
      <Object?>[],
      <String, Object?>{},
    ];
    final List<String> escapes = <String>[];
    void attempt(String label, Map<String, Object?> json) {
      try {
        JetReportFormat.decodeDefinition(json);
      } on ReportFormatException {
        // The contract.
      } catch (e) {
        escapes.add('$label → ${e.runtimeType}');
      }
    }

    for (final List<Object> path in _paths(base)) {
      for (final Object? v in standIns) {
        attempt('$path = ${jsonEncode(v)}', _mutate(base, path, value: v));
      }
      attempt('$path removed', _mutate(base, path, remove: true));
    }
    expect(escapes, isEmpty, reason: escapes.take(20).join('\n'));
  });
}
