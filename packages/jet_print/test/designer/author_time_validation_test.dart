// Phase 4 / T026 (spec 024 / C12): author-time `validate()` diagnostics
// surface in the designer via `controller.diagnostics`, so the editor can flag
// semantic problems (a `$F{}` on record-blind furniture; a duplicate group
// name) without throwing. Consumer-style: public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  group('author-time validation surfaces in the designer (T026)', () {
    test('a clean default definition yields no error diagnostics', () {
      final JetReportDesignerController c = JetReportDesignerController();
      expect(
        c.diagnostics
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
      c.dispose();
    });

    test(r'a $F{} binding on record-blind furniture is flagged', () {
      final ReportDefinition def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        furniture: PageFurniture(
          pageHeader: Band(
            id: 'ph',
            type: BandType.pageHeader,
            height: 24,
            elements: <ReportElement>[
              TextElement(
                id: 't1',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 12),
                text: '',
                expression: r'$F{customerName}',
              ),
            ],
          ),
        ),
        body: const ReportBody(root: DetailScope(id: 'root')),
      );
      final JetReportDesignerController c =
          JetReportDesignerController(definition: def);
      expect(
        c.diagnostics.any((Diagnostic d) => d.elementId == 't1'),
        isTrue,
        reason: 'record-blind furniture must flag a field binding',
      );
      c.dispose();
    });

    test('duplicate group names are flagged as an error', () {
      final ReportDefinition def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            groups: const <GroupLevel>[
              GroupLevel(id: 'g1', name: 'dup', key: r'$F{a}'),
              GroupLevel(id: 'g2', name: 'dup', key: r'$F{b}'),
            ],
          ),
        ),
      );
      final JetReportDesignerController c =
          JetReportDesignerController(definition: def);
      expect(
        c.diagnostics
            .any((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isTrue,
      );
      c.dispose();
    });
  });
}
