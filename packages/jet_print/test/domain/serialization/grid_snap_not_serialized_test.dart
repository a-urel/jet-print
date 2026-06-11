// Grid/snap view-state is NOT serialized (spec 015, US4 / contract C5.3 /
// FR-015, SC-005; Constitution V).
//
// Black-box (public entry point only): grid visibility and snapping are
// ephemeral per-session designer preferences, never part of the report
// document. Toggling them leaves the saved template byte-identical, the JSON
// carries no grid/snap field, and the document round-trips losslessly (so a
// reloaded template renders identically).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _template() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 120,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 10, y: 10, width: 120, height: 16),
              text: 'hello',
            ),
          ],
        ),
      ],
    );

/// Every key appearing anywhere in a decoded-JSON tree.
Set<String> _allKeys(Object? node) {
  final Set<String> keys = <String>{};
  void walk(Object? n) {
    if (n is Map<String, Object?>) {
      for (final MapEntry<String, Object?> e in n.entries) {
        keys.add(e.key);
        walk(e.value);
      }
    } else if (n is List) {
      for (final Object? e in n) {
        walk(e);
      }
    }
  }

  walk(node);
  return keys;
}

void main() {
  test('C5.3 toggling grid/snap leaves the encoded document byte-identical',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(template: _template());
    addTearDown(c.dispose);

    final String before = JetReportFormat.encodeJson(c.template);
    c.setGridEnabled(false);
    c.setSnapEnabled(false);
    c.setGridEnabled(true);
    final String after = JetReportFormat.encodeJson(c.template);

    expect(after, equals(before));
  });

  test('the document carries no grid/snap field at any depth', () {
    final Map<String, Object?> json = JetReportFormat.encode(_template());
    final Set<String> keys = _allKeys(json);

    for (final String forbidden in const <String>[
      'grid',
      'gridEnabled',
      'snap',
      'snapEnabled',
    ]) {
      expect(keys, isNot(contains(forbidden)),
          reason: 'view-only state "$forbidden" must never reach the document');
    }
  });

  test('the document round-trips losslessly (reload renders identically)', () {
    final ReportTemplate original = _template();
    final ReportTemplate reloaded =
        JetReportFormat.decode(JetReportFormat.encode(original));

    // Re-encoding the reloaded template reproduces the original JSON exactly —
    // the lossless guarantee that makes a reloaded design render identically.
    expect(JetReportFormat.encode(reloaded),
        equals(JetReportFormat.encode(original)));
  });
}
