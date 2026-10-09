// Dragging a band's divider stops at the lowest element's bottom edge.
//
// Regression (#32): shrinking a band left elements hanging outside it — the
// drag's only floor was kMinBandHeight. Decided on the issue: the interactive
// drag stops at the content, like a dragged element edge pins at its band
// (non-lossy: nothing is moved or resized); a programmatic SetBandHeightCommand
// is unchanged.
//
// Drives the public controller only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _fixture(List<ReportElement> elements) => ReportDefinition(
      name: 'Bands',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
            id: 'detail',
            type: BandType.detail,
            height: 100,
            elements: elements,
          )),
        ]),
      ),
    );

ShapeElement _shape(String id, double y, double height) => ShapeElement(
    id: id,
    bounds: JetRect(x: 0, y: y, width: 20, height: height),
    kind: ShapeKind.rectangle);

double _height(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().single.band.height;

JetReportDesignerController _open(List<ReportElement> elements) {
  final JetReportDesignerController c =
      JetReportDesignerController(definition: _fixture(elements));
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('the drag stops at the lowest element, which is left untouched', () {
    final JetReportDesignerController c =
        _open(<ReportElement>[_shape('a', 10, 20), _shape('b', 30, 30)]);
    c.beginBandResize('detail');
    c.updateBandResize(-80); // would be 20; content reaches 60

    expect(c.bandResizePreviewHeight('detail'), 60);
    c.commitBandResize();
    expect(_height(c), 60);
    expect(
        c.definition.body.root.children
            .whereType<BandNode>()
            .single
            .band
            .elements
            .map((ReportElement e) => e.bounds),
        <JetRect>[
          const JetRect(x: 0, y: 10, width: 20, height: 20),
          const JetRect(x: 0, y: 30, width: 20, height: 30),
        ]);
  });

  test('growing is unaffected', () {
    final JetReportDesignerController c =
        _open(<ReportElement>[_shape('a', 0, 60)]);
    c.beginBandResize('detail');
    c.updateBandResize(40);
    expect(c.bandResizePreviewHeight('detail'), 140);
  });

  test('an empty band still shrinks to the minimum height', () {
    final JetReportDesignerController c = _open(const <ReportElement>[]);
    c.beginBandResize('detail');
    c.updateBandResize(-1000);
    expect(c.bandResizePreviewHeight('detail'), 8,
        reason: 'kMinBandHeight (design_tunables.dart)');
  });

  test('content already overflowing blocks shrinking but does not grow', () {
    final JetReportDesignerController c =
        _open(<ReportElement>[_shape('a', 90, 40)]); // bottom 130 > 100
    c.beginBandResize('detail');
    c.updateBandResize(-30);
    expect(c.bandResizePreviewHeight('detail'), 100,
        reason: 'cannot shrink below its starting height');
    c.updateBandResize(10);
    expect(c.bandResizePreviewHeight('detail'), 110);
  });
}
