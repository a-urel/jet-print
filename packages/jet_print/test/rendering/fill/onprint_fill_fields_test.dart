// FilledBand.fields carries the originating row's field values (spec 2026-06-27).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

void main() {
  test('FilledBand.fields carries the originating row; {} when rowless', () {
    final ReportDefinition def = ReportDefinition(
      name: 'test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(
          id: 'title',
          type: BandType.title,
          height: 10,
          elements: const <ReportElement>[],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 20,
              elements: <ReportElement>[
                TextElement(
                  id: 'amt',
                  bounds: const JetRect(x: 0, y: 0, width: 80, height: 20),
                  text: 'amt',
                  expression: r'$F{amount}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

    final JetInMemoryDataSource source = JetInMemoryDataSource(
      <Map<String, Object?>>[
        <String, Object?>{'amount': 42},
      ],
      fields: <FieldDef>[
        const FieldDef('amount', type: JetFieldType.integer),
      ],
    );

    final FillResult result = ReportFiller().fillDefinition(def, source);

    // The detail band should carry fields; the title band (rowless) should have {}
    final FilledBand detail =
        result.report.bands.firstWhere((b) => b.type == BandType.detail);
    final FilledBand title =
        result.report.bands.firstWhere((b) => b.type == BandType.title);

    expect(detail.fields['amount'], const JetNumber(42));
    expect(title.fields, isEmpty);
  });
}
