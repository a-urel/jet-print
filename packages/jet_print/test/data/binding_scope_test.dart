// Binding scope resolution across arbitrary master/detail nesting (US3 /
// FR-016, FR-017, FR-018). Pure logic — white-box (data seam) test.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/binding_scope.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';

const JetDataSchema _schema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('description', type: JetFieldType.string),
        FieldDef(
          'subLines',
          type: JetFieldType.collection,
          fields: <FieldDef>[FieldDef('sku', type: JetFieldType.string)],
        ),
      ],
    ),
  ],
);

List<String> _names(List<FieldDef> fields) =>
    fields.map((FieldDef f) => f.name).toList();

void main() {
  group('fieldsInScopeAt', () {
    test('master scope (empty path) is the root fields', () {
      const ReportTemplate t =
          ReportTemplate(name: 'r', page: PageFormat.a4Portrait);
      expect(_names(fieldsInScopeAt(_schema, t, const <int>[])),
          <String>['customerName', 'lines']);
    });

    test('inside a lines-bound band, scope is the line fields', () {
      const ReportTemplate t = ReportTemplate(
        name: 'r',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
              type: BandType.detail, height: 50, collectionField: 'lines'),
        ],
      );
      final List<String> scope =
          _names(fieldsInScopeAt(_schema, t, const <int>[0]));
      expect(scope, containsAll(<String>['description', 'subLines']));
      expect(scope, isNot(contains('customerName')));
    });

    test('a nested subLines-bound band sees sub-line fields (arbitrary depth)',
        () {
      const ReportTemplate t = ReportTemplate(
        name: 'r',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 50,
            collectionField: 'lines',
            children: <ReportBand>[
              ReportBand(
                  type: BandType.detail,
                  height: 20,
                  collectionField: 'subLines'),
            ],
          ),
        ],
      );
      expect(_names(fieldsInScopeAt(_schema, t, const <int>[0, 0])),
          <String>['sku']);
    });
  });

  group('resolution', () {
    test('expressionResolves checks field refs against scope', () {
      const ReportTemplate t =
          ReportTemplate(name: 'r', page: PageFormat.a4Portrait);
      final List<FieldDef> master = fieldsInScopeAt(_schema, t, const <int>[]);
      expect(expressionResolves(master, r'$F{customerName}'), isTrue);
      expect(expressionResolves(master, r'$F{description}'), isFalse); // child
      expect(expressionResolves(master, r'upper($F{customerName})'), isTrue);
      expect(expressionResolves(master, r'$P{p}'), isTrue); // no field refs
    });

    test('fieldResolves checks a single field name', () {
      const ReportTemplate t =
          ReportTemplate(name: 'r', page: PageFormat.a4Portrait);
      final List<FieldDef> master = fieldsInScopeAt(_schema, t, const <int>[]);
      expect(fieldResolves(master, 'customerName'), isTrue);
      expect(fieldResolves(master, 'nope'), isFalse);
    });
  });

  test('bandPathOfElement locates an element in a nested band', () {
    const ReportTemplate t = ReportTemplate(
      name: 'r',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 50,
          collectionField: 'lines',
          children: <ReportBand>[
            ReportBand(
              type: BandType.detail,
              height: 20,
              collectionField: 'subLines',
              elements: <ReportElement>[
                TextElement(
                  id: 'deep',
                  bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
                  text: 'x',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(bandPathOfElement(t, 'deep'), <int>[0, 0]);
    expect(bandPathOfElement(t, 'missing'), isNull);
  });
}
