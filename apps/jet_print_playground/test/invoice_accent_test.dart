// Confirms the invoice sample carries a few accent stripes — a title underline
// bar, a column-header rule, a rule above the Grand Total, and a tick beside
// each footer section label — authored as ShapeElements through the public API.
// Pure presentation: it must keep the definition pristine under the validator.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/invoice_sample.dart';

/// The playground accent blue (shared with the List demo).
const JetColor _accent = JetColor(0xFF2F5C8A);

void main() {
  group('invoice accent stripes', () {
    Band header() => invoiceSampleDefinition().body.root.groups.single.header!;
    Band footer() => invoiceSampleDefinition().body.root.groups.single.footer!;
    ShapeElement shapeIn(Band b, String id) =>
        b.elements.firstWhere((ReportElement e) => e.id == id) as ShapeElement;

    test('the INVOICE title has a short accent underline bar', () {
      final ShapeElement s = shapeIn(header(), 'titleAccent');
      expect(s.kind, ShapeKind.rectangle);
      expect(s.style.fill, _accent);
      expect(s.bounds.y, greaterThanOrEqualTo(28),
          reason: 'sits below the 28pt-tall heading');
      expect(s.bounds.width, lessThan(300),
          reason: 'a short accent bar, not a full-width rule');
    });

    test('the column-header row is set off by a full-width accent rule', () {
      final ShapeElement s = shapeIn(header(), 'tableHeaderRule');
      expect(s.kind, ShapeKind.rectangle);
      expect(s.style.fill, _accent);
      expect(s.bounds.width, greaterThanOrEqualTo(500),
          reason: 'spans the table columns');
    });

    test('an accent rule sits above the Grand Total', () {
      final ShapeElement s = shapeIn(footer(), 'grandTotalRule');
      expect(s.kind, ShapeKind.rectangle);
      expect(s.style.fill, _accent);
      expect(s.bounds.y, lessThan(84),
          reason: 'above the grand total line at y=84');
    });

    test('each footer section label carries a thin accent tick', () {
      for (final String id in <String>[
        'paymentTermsTick',
        'shippingTick',
        'descriptionTick',
      ]) {
        final ShapeElement s = shapeIn(footer(), id);
        expect(s.kind, ShapeKind.rectangle);
        expect(s.style.fill, _accent);
        expect(s.bounds.x, 0, reason: 'tick hugs the left margin');
        expect(s.bounds.width, lessThanOrEqualTo(6),
            reason: 'a thin vertical tick, not a block');
      }
    });

    test('the accent stripes keep the definition pristine under the validator',
        () {
      expect(validate(invoiceSampleDefinition()), isEmpty);
    });
  });
}
