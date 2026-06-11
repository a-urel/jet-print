// Ruler metrics — points↔mm conversion contract (spec 014, C2.1–2 / FR-003,
// FR-005). White-box unit test of the pure display-only projection over the
// model's point geometry; `selectionExtent` (C2.3–7) is added in US4.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/designer/canvas/ruler_metrics.dart';
import 'package:jet_print/src/designer/controller/selection.dart';

/// A two-band template (page header + detail) with two detail elements at known
/// band-relative positions, for exercising `selectionExtent`.
ReportTemplate _template() => const ReportTemplate(
      name: 'extent',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(type: BandType.pageHeader, height: 60),
        ReportBand(
          type: BandType.detail,
          height: 200,
          elements: <ReportElement>[
            TextElement(
              id: 'a',
              bounds: JetRect(x: 10, y: 10, width: 50, height: 20),
              text: 'A',
            ),
            TextElement(
              id: 'b',
              bounds: JetRect(x: 100, y: 60, width: 40, height: 30),
              text: 'B',
            ),
          ],
        ),
      ],
    );

void main() {
  group('ruler metrics — conversion (C2.1, FR-005)', () {
    test('kPointsPerMm is exactly 72/25.4', () {
      expect(kPointsPerMm, 72 / 25.4);
    });

    test('points↔mm round-trips both ways within float epsilon', () {
      for (final double x in <double>[0, 1, 12.5, 100, 595.275, 1000]) {
        expect(pointsToMm(mmToPoints(x)), closeTo(x, 1e-9));
        expect(mmToPoints(pointsToMm(x)), closeTo(x, 1e-9));
      }
    });
  });

  group('ruler metrics — origin (C2.2, FR-003)', () {
    test('page point 0 converts to 0 mm', () {
      expect(pointsToMm(0), 0);
    });

    test('an A4 page width (595.275 pt) converts to 210 mm', () {
      // 210 mm is A4's physical width; 595.275 pt = 210 · 72/25.4.
      expect(pointsToMm(595.275), closeTo(210, 1e-3));
    });
  });

  group('selectionExtent (C2.3–7, FR-012)', () {
    final ReportTemplate template = _template();
    final DesignTimeLayout layout = DesignTimeLayout.of(template);

    test('a single element returns its page-absolute rect (C2.3)', () {
      final JetRect? extent =
          selectionExtent(layout, Selection.of(const <String>['a']));
      expect(extent, layout.elementRect('a'));
    });

    test('multiple elements return one combined union rect (C2.4)', () {
      final JetRect? extent =
          selectionExtent(layout, Selection.of(const <String>['a', 'b']));
      final JetRect a = layout.elementRect('a')!;
      final JetRect b = layout.elementRect('b')!;
      expect(extent, isNotNull);
      expect(extent!.x, a.x); // a is left-most
      expect(extent.y, a.y); // a is top-most
      expect(extent.x + extent.width, b.x + b.width); // b is right-most
      expect(extent.y + extent.height, b.y + b.height); // b is bottom-most
    });

    test('the union is independent of selection order (C2.7)', () {
      expect(
        selectionExtent(layout, Selection.of(const <String>['a', 'b'])),
        selectionExtent(layout, Selection.of(const <String>['b', 'a'])),
      );
    });

    test('a band selection returns the band rect (C2.5)', () {
      expect(selectionExtent(layout, Selection.band(1)), layout.bandRect(1));
    });

    test('a report or empty selection returns null (C2.6)', () {
      expect(selectionExtent(layout, Selection.report()), isNull);
      expect(selectionExtent(layout, Selection.empty), isNull);
    });

    test('an absent element id contributes nothing (and alone is null)', () {
      expect(selectionExtent(layout, Selection.of(const <String>['ghost'])),
          isNull);
      // A real element mixed with a ghost still yields the real one's rect.
      expect(selectionExtent(layout, Selection.of(const <String>['a', 'ghost'])),
          layout.elementRect('a'));
    });
  });
}
