// The kitchen-ticket sample is structurally valid: `validate()` is what the
// designer shows as diagnostics, and a sample rendered headlessly never runs
// it (docs/recipes/add-playground-demo.md, step 4). Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/kitchen_ticket_sample.dart';

void main() {
  test('the kitchen-ticket definition validates clean, with its schema too',
      () {
    expect(validate(kitchenTicketDefinition()), isEmpty);
    // With a schema, validate also checks aggregate operands against it. The
    // ticket has none; that its bindings resolve against the schema is pinned
    // by the render test, which allows no unresolved-field warning.
    expect(validate(kitchenTicketDefinition(), schema: kitchenTicketSchema),
        isEmpty);
  });

  test('it is an 80 mm roll, not a sheet', () {
    final PageFormat page = kitchenTicketDefinition().page;
    expect(page.continuous, isTrue);
    // 80 mm in PostScript points.
    expect(page.width, closeTo(80 / 25.4 * 72, 0.01));
  });

  test('one ticket per station: the station group starts a new page', () {
    final GroupLevel station =
        kitchenTicketDefinition().body.root.groups.single;
    expect(station.key, r'$F{station}');
    expect(station.startNewPage, isTrue);
  });
}
