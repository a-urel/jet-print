import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_codec.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_definition_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

const Crosstab _minimal = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}'),
  ],
  columnGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}'),
  ],
  measures: <CrosstabMeasure>[
    CrosstabMeasure(
      id: 'm/a',
      name: 'A',
      expression: r'$F{amount}',
      aggregate: JetCalculation.sum,
    ),
  ],
);

ElementCodecRegistry _registry() {
  final ElementCodecRegistry r = ElementCodecRegistry();
  registerBuiltInElementCodecs(r);
  return r;
}

void main() {
  group('crosstab codec', () {
    test('round-trips a minimal crosstab', () {
      expect(decodeCrosstab(encodeCrosstab(_minimal)), equals(_minimal));
    });

    test('omits defaults', () {
      final Map<String, Object?> json = encodeCrosstab(_minimal);
      expect(json.containsKey('style'), isFalse);
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('collectionField'), isFalse);
      final Map<String, Object?> g =
          (json['rowGroups']! as List<Object?>).first! as Map<String, Object?>;
      expect(g.containsKey('sort'), isFalse, reason: 'ascending is default');
      expect(g.containsKey('showTotal'), isFalse, reason: 'true is default');
    });

    test('round-trips a fully populated crosstab', () {
      final Crosstab full = _minimal.copyWith(
        name: () => 'Sales',
        collectionField: () => 'lines',
        visible: const BoolProperty(value: false),
        style: const CrosstabStyle(
          headerText: JetTextStyle(weight: JetFontWeight.bold),
          headerBox: JetBoxStyle(fill: JetColor.fromARGB(255, 230, 230, 230)),
          cellText: JetTextStyle(italic: true),
          cellBox: JetBoxStyle(stroke: JetColor.fromARGB(255, 0, 0, 0)),
          totalText: JetTextStyle(underline: true),
          totalBox: JetBoxStyle(fill: JetColor.fromARGB(255, 255, 255, 0)),
          rowLabelWidth: 90,
          rowHeight: 16,
        ),
        rowGroups: <CrosstabGroup>[
          _minimal.rowGroups.first.copyWith(
            sort: CrosstabSort.descending,
            showTotal: false,
            totalLabel: () => 'All regions',
          ),
        ],
        columnGroups: <CrosstabGroup>[
          _minimal.columnGroups.first.copyWith(
            sort: CrosstabSort.descending,
            showTotal: false,
            totalLabel: () => 'All quarters',
          ),
        ],
        measures: <CrosstabMeasure>[
          _minimal.measures.first.copyWith(
            aggregate: JetCalculation.average,
            format: () => '#,##0.00',
            cellTextStyle: () => const JetTextStyle(fontSize: 9),
            cellBoxStyle: () =>
                const JetBoxStyle(fill: JetColor.fromARGB(255, 200, 220, 255)),
          ),
        ],
      );
      expect(decodeCrosstab(encodeCrosstab(full)), equals(full));
    });

    test('a crosstab survives a whole-definition round-trip', () {
      final ReportDefinition def = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: const ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(id: 'd', type: BandType.detail, height: 12)),
              CrosstabNode(_minimal),
            ],
          ),
        ),
      );
      final ReportDefinition back =
          decodeDefinition(encodeDefinition(def, _registry()), _registry());
      expect(back, equals(def));
    });

    test('an unknown scope-node kind round-trips instead of throwing', () {
      final Map<String, Object?> json = encodeDefinition(
        ReportDefinition(
          name: 'R',
          page: PageFormat.a4Portrait,
          body: const ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[]),
          ),
        ),
        _registry(),
      );
      final Map<String, Object?> body = json['body']! as Map<String, Object?>;
      final Map<String, Object?> root = body['root']! as Map<String, Object?>;
      const Map<String, Object?> alien = <String, Object?>{
        'kind': 'sparkline',
        'payload': <String, Object?>{'id': 'x1'},
      };
      root['children'] = <Object?>[alien];

      final ReportDefinition back = decodeDefinition(json, _registry());
      final ScopeNode node = back.body.root.children.single;
      expect(node, isA<UnknownScopeNode>());
      expect((node as UnknownScopeNode).rawJson, alien);

      final Map<String, Object?> reJson = encodeDefinition(back, _registry());
      final Map<String, Object?> reBody =
          reJson['body']! as Map<String, Object?>;
      final Map<String, Object?> reRoot =
          reBody['root']! as Map<String, Object?>;
      expect((reRoot['children']! as List<Object?>).single, alien);
    });
  });
}
