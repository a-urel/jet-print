// Ruler metrics — points↔mm conversion contract (spec 014, C2.1–2 / FR-003,
// FR-005). White-box unit test of the pure display-only projection over the
// model's point geometry; `selectionExtent` (C2.3–7) is added in US4.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/ruler_metrics.dart';

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
}
