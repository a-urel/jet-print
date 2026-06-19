// Confirms the nested-list sample emphasises its groups visually (shaded bands
// + rules) so the Customer and Order groupings read at a glance — authored as
// background ShapeElements layered behind the existing text, through the public
// API only. Pure presentation: it must not perturb the text content or the
// library validator.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/nested_list_sample.dart';

void main() {
  group('nested-list group emphasis', () {
    test('the customer header opens with a full-width shaded background', () {
      final ReportDefinition def = nestedListsDefinition();
      final Band header = def.body.root.groups.single.header!;

      // A filled rectangle, drawn first so the name/code text paints over it.
      final ReportElement first = header.elements.first;
      expect(first, isA<ShapeElement>(),
          reason: 'the band background is layered behind the text');
      final ShapeElement bg = first as ShapeElement;
      expect(bg.kind, ShapeKind.rectangle);
      expect(bg.style.fill, isNotNull, reason: 'a shaded band, not an outline');
      expect(bg.bounds.width, greaterThanOrEqualTo(500),
          reason: 'spans the content width');

      // An accent rule below the text reinforces the section break.
      final List<ShapeElement> shapes =
          header.elements.whereType<ShapeElement>().toList();
      expect(shapes.length, greaterThanOrEqualTo(2),
          reason: 'background fill + accent rule');
    });

    test('each order line is tinted and its column headers are underlined', () {
      final ReportDefinition def = nestedListsDefinition();
      final DetailScope orders =
          (def.body.root.children.single as NestedScope).scope;
      final Band orderRow = (orders.children.first as BandNode).band;

      // The order tint is drawn first (behind the order no/date + col titles).
      expect(orderRow.elements.first, isA<ShapeElement>());
      final List<ShapeElement> shapes =
          orderRow.elements.whereType<ShapeElement>().toList();
      expect(shapes.length, greaterThanOrEqualTo(2),
          reason: 'order tint + column-header hairline');
      expect(shapes.every((ShapeElement s) => s.kind == ShapeKind.rectangle),
          isTrue);
      expect(shapes.every((ShapeElement s) => s.style.fill != null), isTrue);
    });

    test('the customer total is separated by a rule', () {
      final ReportDefinition def = nestedListsDefinition();
      final Band footer = def.body.root.groups.single.footer!;
      expect(footer.elements.whereType<ShapeElement>(), isNotEmpty,
          reason: 'a rule above the customer total closes the section');
    });

    test('the grand total is separated by a matching rule', () {
      final ReportDefinition def = nestedListsDefinition();
      expect(def.body.summary!.elements.whereType<ShapeElement>(), isNotEmpty,
          reason: 'the summary mirrors the customer-total rule');
    });

    test('emphasis keeps the definition pristine under the validator', () {
      expect(validate(nestedListsDefinition()), isEmpty,
          reason: 'decorative shapes introduce no diagnostics');
    });
  });
}
