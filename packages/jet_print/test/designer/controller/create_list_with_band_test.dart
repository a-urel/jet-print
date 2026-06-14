// Controller unit test: createListWithBand creates a nested list AND a detail
// band as one undo step, selecting the band.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('createListWithBand adds a bound nested scope with a detail band, selecting the band', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');

    final List<NestedScope> nested =
        c.definition.body.root.children.whereType<NestedScope>().toList();
    expect(nested, hasLength(1), reason: 'a nested list scope was created');
    final DetailScope list = nested.single.scope;
    expect(list.collectionField, 'lines');
    final List<BandNode> bands = list.children.whereType<BandNode>().toList();
    expect(bands, hasLength(1), reason: 'the list has one detail band');
    expect(bands.single.band.type, BandType.detail);
    expect(c.selection.bandId, bands.single.band.id,
        reason: 'the new detail band is selected');
  });

  test('createListWithBand is one undo step (undo removes both scope and band)', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;

    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    c.undo();

    expect(c.definition, before, reason: 'a single undo reverts the whole gesture');
  });

  test('createListWithBand is a no-op for an unknown parent scope', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createListWithBand('nope', collectionField: 'lines');
    expect(c.definition, before);
  });
}
