// Render does not validate (#98). `validate` is opt-in: the engine draws a
// definition validation rejects, best effort, and reports only what rendering
// itself found. 0004's output promise covers only definitions `validate`
// accepts, which is what keeps a validation check added later from changing
// any render's diagnostics.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A summary slot holding a band typed `detail`: a slot error (I5) for
/// `validate`, but nothing the render path trips over.
const ReportDefinition _misSlotted = ReportDefinition(
  name: 'mis-slotted',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    summary: Band(
      id: 'summary',
      type: BandType.detail,
      height: 20,
      elements: <ReportElement>[
        TextElement(
          id: 'total',
          bounds: JetRect(x: 0, y: 0, width: 100, height: 16),
          text: 'Total',
        ),
      ],
    ),
    root: DetailScope(id: 'root'),
  ),
);

void main() {
  test('validate reports the mis-slotted band as an error', () {
    final List<Diagnostic> found = validate(_misSlotted);
    expect(found.hasErrors, isTrue);
    expect(found.map((Diagnostic d) => d.message), contains(contains('slot')));
  });

  test('render draws it anyway and does not report validation findings', () {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _misSlotted,
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );
    expect(report.pageCount, 1);
    // Build the page too: frames are built lazily, so this covers the whole
    // render path, not only pagination.
    report.pageAt(0);
    expect(report.diagnostics.hasErrors, isFalse);
    expect(report.diagnostics.entries.map((Diagnostic d) => d.message),
        isNot(contains(contains('slot'))));
  });
}
