import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_validation.dart';

ReportDefinition _def(DetailScope root) => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(root: root),
    );

bool _info(List<Diagnostic> ds, String needle) => ds.any((Diagnostic d) =>
    d.severity == DiagnosticSeverity.info &&
    d.message.toLowerCase().contains(needle));

void main() {
  group('deferred capabilities (representable but not yet rendered — I7)', () {
    test('a non-root scope carrying groups is representable', () {
      // Constructs without error — the model can hold it.
      const DetailScope root = DetailScope(
        id: 'root',
        children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'root/c0',
            collectionField: 'lines',
            groups: <GroupLevel>[GroupLevel(id: 'g', name: 'n', key: '1')],
          )),
        ],
      );
      expect(root.children, hasLength(1));
    });

    test('validate() emits an info diagnostic for per-scope grouping', () {
      final ReportDefinition def = _def(const DetailScope(
        id: 'root',
        children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'root/c0',
            collectionField: 'lines',
            groups: <GroupLevel>[GroupLevel(id: 'g', name: 'n', key: '1')],
          )),
        ],
      ));
      final List<Diagnostic> ds = validate(def);
      expect(_info(ds, 'not yet rendered'), isTrue);
      // It is an info, not an error — the shape is allowed.
      expect(ds.any((Diagnostic d) => d.severity == DiagnosticSeverity.error),
          isFalse);
    });

    test('a scope with more than one per-row band is representable', () {
      const DetailScope scope = DetailScope(
        id: 'root/c0',
        collectionField: 'lines',
        children: <ScopeNode>[
          BandNode(Band(id: 'a', type: BandType.detail, height: 10)),
          BandNode(Band(id: 'b', type: BandType.detail, height: 10)),
        ],
      );
      expect(scope.children.whereType<BandNode>(), hasLength(2));
    });

    test('validate() emits an info diagnostic for multiple per-row bands', () {
      final ReportDefinition def = _def(const DetailScope(
        id: 'root',
        children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'root/c0',
            collectionField: 'lines',
            children: <ScopeNode>[
              BandNode(Band(id: 'a', type: BandType.detail, height: 10)),
              BandNode(Band(id: 'b', type: BandType.detail, height: 10)),
            ],
          )),
        ],
      ));
      expect(_info(validate(def), 'not yet rendered'), isTrue);
    });
  });
}
