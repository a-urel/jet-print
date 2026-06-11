// Ruler alignment under zoom + pan (spec 014, C4 / FR-004, FR-008, FR-009,
// SC-002). Mirrors zoom_pan_test.dart / page_scroll_test.dart: drives the public
// designer, then asserts the ruler marks stay locked to true page positions as
// the view scales and scrolls. The core invariant — a tick labelled M mm sits at
// the page's left/top edge plus M·(72/25.4)·scale pixels — is checked directly
// against the live page surface, so any drift is caught.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const Key _kHorizontalRuler =
    ValueKey<String>('jet_print.designer.ruler.horizontal');
const Key _kVerticalRuler =
    ValueKey<String>('jet_print.designer.ruler.vertical');

/// Points per millimetre (mirrors `ruler_metrics.dart`'s kPointsPerMm).
const double _pointsPerMm = 72 / 25.4;

ScrollableState _scrollable(WidgetTester tester, Axis axis) => tester
    .stateList<ScrollableState>(
      find.descendant(
        of: find.byKey(kDesignCanvasKey),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((ScrollableState s) => s.position.axis == axis);

/// The integer mm value parsed from a ruler label's [text], or null. Keeps the
/// sign — the ruler legitimately shows negative mm in the margin before the page
/// origin — and strips only locale grouping separators.
int? _mm(String? text) =>
    text == null ? null : int.tryParse(text.replaceAll(RegExp('[^0-9-]'), ''));

/// The visible labels on a HORIZONTAL [ruler] as (mm, screen-x). The label Text
/// is upright, so its top-left x is the tick x (plus the small fixed offset).
List<(int, double)> _hLabels(WidgetTester tester, Finder ruler) {
  final List<(int, double)> out = <(int, double)>[];
  for (final Element e
      in find.descendant(of: ruler, matching: find.byType(Text)).evaluate()) {
    final int? mm = _mm((e.widget as Text).data);
    if (mm == null) continue;
    out.add((mm, tester.getTopLeft(find.byWidget(e.widget)).dx));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// The visible labels on the VERTICAL [ruler] as (mm, screen-y). The labels are
/// rotated (so the Text's own bounds shift with digit-count), so the stable
/// anchor is the enclosing RotatedBox's top — its Positioned y, independent of
/// the label's character width.
List<(int, double)> _vLabels(WidgetTester tester, Finder ruler) {
  final List<(int, double)> out = <(int, double)>[];
  for (final Element box
      in find.descendant(of: ruler, matching: find.byType(RotatedBox)).evaluate()) {
    final Finder text =
        find.descendant(of: find.byWidget(box.widget), matching: find.byType(Text));
    if (text.evaluate().isEmpty) continue;
    final int? mm = _mm(tester.widget<Text>(text).data);
    if (mm == null) continue;
    out.add((mm, tester.getTopLeft(find.byWidget(box.widget)).dy));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Asserts every horizontal label sits at the page-left edge + M·pxPerMm·scale
/// (within a few px of slop for the label's small offset from its tick line).
void _assertHorizontalAligned(WidgetTester tester, double scale) {
  final double pageLeft = tester.getRect(find.byKey(kDesignPageKey)).left;
  final List<(int, double)> labels =
      _hLabels(tester, find.byKey(_kHorizontalRuler));
  expect(labels, isNotEmpty);
  for (final (int mm, double x) in labels) {
    final double expected = pageLeft + mm * _pointsPerMm * scale;
    expect((x - expected).abs(), lessThan(4.0),
        reason: 'label $mm mm drifted from its page position');
  }
}

/// The smallest gap (mm) between consecutive labelled ticks — i.e. the chosen
/// labelled step, used to assert it re-steps finer/coarser with zoom.
int _labelStep(WidgetTester tester) {
  final List<(int, double)> labels =
      _hLabels(tester, find.byKey(_kHorizontalRuler));
  int step = 1 << 30;
  for (int i = 1; i < labels.length; i++) {
    final int gap = labels[i].$1 - labels[i - 1].$1;
    step = gap < step ? gap : step;
  }
  return step;
}

void main() {
  testWidgets('at default zoom an element edge aligns with its mm mark (C4.1)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    _assertHorizontalAligned(tester, c.viewScale);
  });

  testWidgets('zoom in/out keeps alignment and re-steps the labels (C4.2)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final int stepDefault = _labelStep(tester);

    c.zoomIn();
    c.zoomIn();
    await tester.pumpAndSettle();
    _assertHorizontalAligned(tester, c.viewScale);
    final int stepIn = _labelStep(tester);
    expect(stepIn, lessThanOrEqualTo(stepDefault),
        reason: 'zooming in shows the same or a finer labelled step');

    c.zoomOut();
    c.zoomOut();
    c.zoomOut();
    c.zoomOut();
    await tester.pumpAndSettle();
    _assertHorizontalAligned(tester, c.viewScale);
    expect(_labelStep(tester), greaterThanOrEqualTo(stepIn),
        reason: 'zooming back out shows the same or a coarser labelled step');
  });

  testWidgets('vertical pan shifts the left ruler with the page (C4.3)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final ScrollableState v = _scrollable(tester, Axis.vertical);
    expect(v.position.maxScrollExtent, greaterThan(0));

    final int firstBefore =
        _vLabels(tester, find.byKey(_kVerticalRuler)).first.$1;

    v.position.jumpTo(220);
    await tester.pumpAndSettle();

    final List<(int, double)> after =
        _vLabels(tester, find.byKey(_kVerticalRuler));
    expect(after.length, greaterThanOrEqualTo(2));
    // Scrolling down brings larger mm into view: the first visible label grew.
    expect(after.first.$1, greaterThan(firstBefore),
        reason: 'the left ruler must scroll with the page');
    // …and the marks stay locked to the page scale: the screen gap between two
    // labels equals their mm difference · pxPerMm · scale. (Spacing is immune to
    // the labels' rotation, which shifts every label by the same constant.)
    final double pxPerMm = _pointsPerMm * c.viewScale;
    for (int i = 1; i < after.length; i++) {
      final double expectedGap = (after[i].$1 - after[i - 1].$1) * pxPerMm;
      expect((after[i].$2 - after[i - 1].$2 - expectedGap).abs(), lessThan(1.0),
          reason: 'left-ruler spacing drifted from the page scale while panning');
    }
  });

  testWidgets('horizontal pan shifts the top ruler with the page (C4.3)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    // Zoom in so the page overflows the width and can be panned horizontally.
    c.zoomIn();
    c.zoomIn();
    c.zoomIn();
    await tester.pumpAndSettle();
    final ScrollableState h = _scrollable(tester, Axis.horizontal);
    expect(h.position.maxScrollExtent, greaterThan(0));

    final int firstBefore =
        _hLabels(tester, find.byKey(_kHorizontalRuler)).first.$1;

    h.position.jumpTo(180);
    await tester.pumpAndSettle();

    _assertHorizontalAligned(tester, c.viewScale);
    expect(
        _hLabels(tester, find.byKey(_kHorizontalRuler)).first.$1,
        greaterThan(firstBefore),
        reason: 'the top ruler must scroll with the page; first label updates');
  });
}
