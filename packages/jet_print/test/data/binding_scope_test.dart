// Binding scope resolution across arbitrary master/detail nesting (US3 /
// FR-016, FR-017, FR-018). Pure logic — white-box (data seam) test.
//
// Reification (spec 024): a band's data scope is the chain of [DetailScope]s
// enclosing it. The designer computes that chain with [scopePathToBand] (and
// the band owning an element with [findBandOfElement]); the data seam then
// resolves the schema for that chain via [fieldsInScopeForChain]. These tests
// drive the same path the designer does: build the reified tree, walk it to the
// band's scope chain, and assert the fields in scope.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/binding_scope.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';

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

/// The fields in scope for the band [bandId] in [def], resolved exactly as the
/// designer does: walk the tree to the band's enclosing scope chain, then
/// descend the schema through that chain.
List<FieldDef> _fieldsInScopeOf(ReportDefinition def, String bandId) =>
    fieldsInScopeForChain(_schema, scopePathToBand(def, bandId));

void main() {
  group('fieldsInScope', () {
    test('master scope (empty chain) is the root fields', () {
      // A once-band (e.g. furniture/title) resolves against the root/master
      // schema: an empty scope chain yields the top-level fields.
      expect(_names(fieldsInScopeForChain(_schema, const <DetailScope>[])),
          <String>['customerName', 'lines']);
    });

    test('inside a lines-bound band, scope is the line fields', () {
      final ReportDefinition def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(id: 'line', type: BandType.detail, height: 50)),
                ],
              )),
            ],
          ),
        ),
      );
      final List<String> scope = _names(_fieldsInScopeOf(def, 'line'));
      expect(scope, containsAll(<String>['description', 'subLines']));
      expect(scope, isNot(contains('customerName')));
    });

    test('a nested subLines-bound band sees sub-line fields (arbitrary depth)',
        () {
      final ReportDefinition def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  NestedScope(DetailScope(
                    id: 'subLines',
                    collectionField: 'subLines',
                    children: <ScopeNode>[
                      BandNode(Band(
                          id: 'subLine', type: BandType.detail, height: 20)),
                    ],
                  )),
                ],
              )),
            ],
          ),
        ),
      );
      expect(_names(_fieldsInScopeOf(def, 'subLine')), <String>['sku']);
    });
  });

  group('resolution', () {
    test('expressionResolves checks field refs against scope', () {
      final List<FieldDef> master =
          fieldsInScopeForChain(_schema, const <DetailScope>[]);
      expect(expressionResolves(master, r'$F{customerName}'), isTrue);
      expect(expressionResolves(master, r'$F{description}'), isFalse); // child
      expect(expressionResolves(master, r'upper($F{customerName})'), isTrue);
      expect(expressionResolves(master, r'$P{p}'), isTrue); // no field refs
    });

    test('fieldResolves checks a single field name', () {
      final List<FieldDef> master =
          fieldsInScopeForChain(_schema, const <DetailScope>[]);
      expect(fieldResolves(master, 'customerName'), isTrue);
      expect(fieldResolves(master, 'nope'), isFalse);
    });
  });

  test('findBandOfElement locates an element in a nested band', () {
    final ReportDefinition def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                NestedScope(DetailScope(
                  id: 'subLines',
                  collectionField: 'subLines',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'subLine',
                      type: BandType.detail,
                      height: 20,
                      elements: <ReportElement>[
                        TextElement(
                          id: 'deep',
                          bounds:
                              const JetRect(x: 0, y: 0, width: 10, height: 10),
                          text: 'x',
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
    expect(findBandOfElement(def, 'deep')?.id, 'subLine');
    expect(findBandOfElement(def, 'missing'), isNull);
  });
}
