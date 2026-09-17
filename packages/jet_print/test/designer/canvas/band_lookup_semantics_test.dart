// `bandIdAt` and `bandIdNear` are a lookalike pair, and the difference between
// them is the whole point of having both: one SNAPS to the nearest band, the
// other does not. Four comments in this repo got that backwards at once (two of
// them naming `bandIdAt` as the snapping one), so the distinction is pinned here
// rather than described again.
//
//   * `bandIdAt`   — click selection. No fallback: a point in the flow gap is on
//                    no band, and the canvas resolves it to the report/page.
//   * `bandIdNear` — drops. Always answers a band, so a dropped field or tool
//                    lands somewhere valid.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';

// A4 portrait: 841.89pt tall, 28.35pt margins. One 40pt page header and one
// 50pt detail band flow from the top margin; the 30pt page footer is anchored to
// the bottom. That leaves a tall empty flow gap between them — the shape a real
// half-authored report has, and where the snap fallback shows itself. The two
// lookups also disagree at a shared band seam, for an unrelated reason; both
// cases are pinned at the bottom of this file.
const Band _header = Band(id: 'hdr', type: BandType.pageHeader, height: 40);
const Band _detail = Band(id: 'det', type: BandType.detail, height: 50);
const Band _footer = Band(id: 'ftr', type: BandType.pageFooter, height: 30);

final DesignTimeLayout _layout = DesignTimeLayout.of(const ReportDefinition(
  name: 'R',
  page: PageFormat.a4Portrait,
  furniture: PageFurniture(pageHeader: _header, pageFooter: _footer),
  body: ReportBody(
    root: DetailScope(id: 'root', children: <ScopeNode>[BandNode(_detail)]),
  ),
));

/// A point in the empty flow gap: below the detail band's bottom edge
/// (28.35 + 40 + 50 = 118.35) and above the bottom-anchored footer's top edge
/// (841.89 - 28.35 - 30 = 783.54). Nearer the detail band than the footer, so a
/// snapping lookup must answer `det` — proving it picked the NEAREST band and
/// not merely the first or the last.
const JetOffset _inTheGap = JetOffset(100, 400);

void main() {
  group('bandIdAt — click selection, never snaps', () {
    test('a point in the empty flow gap is on no band', () {
      // Fails if `bandIdAt` ever grows a nearest-band fallback — i.e. if the
      // comments that claimed it snaps were made true.
      expect(_layout.bandIdAt(_inTheGap), isNull);
    });

    test('a point below the whole sheet is on no band', () {
      expect(_layout.bandIdAt(const JetOffset(100, 2000)), isNull);
    });

    test('a point inside a band resolves to that band', () {
      expect(_layout.bandIdAt(const JetOffset(100, 100)), 'det');
    });
  });

  group('bandIdNear — drops, always answers a band', () {
    test('a point in the empty flow gap snaps to the vertically nearest band',
        () {
      // Fails if `bandIdNear` loses its nearest-band fallback, which would make
      // a drop into the gap land nowhere.
      expect(_layout.bandIdNear(_inTheGap), 'det');
    });

    test('a point below the whole sheet snaps upward to the footer', () {
      // The footer is the nearest band from below; `det` is nearest from the
      // gap. One fixture, two directions — so a fallback that always answered
      // the same band would fail one of them.
      expect(_layout.bandIdNear(const JetOffset(100, 2000)), 'ftr');
    });

    test('a point inside a band resolves to that band', () {
      expect(_layout.bandIdNear(const JetOffset(100, 100)), 'det');
    });
  });

  test('in the gap, one declines and the other snaps', () {
    // The property the stale comments erased: in the flow gap `bandIdAt`
    // resolves to nothing and `bandIdNear` still answers a band.
    expect(_layout.bandIdAt(_inTheGap), isNull);
    expect(_layout.bandIdNear(_inTheGap), isNotNull);
  });

  test('strictly inside a band the two lookups agree', () {
    // Interior points only. NOT "they agree wherever a band contains the
    // point" — see the seam case below, which is why this is worded narrowly.
    for (final double dy in <double>[40, 100]) {
      expect(_layout.bandIdAt(JetOffset(100, dy)),
          _layout.bandIdNear(JetOffset(100, dy)),
          reason: 'interior point dy=$dy');
    }
  });

  test('at a shared band seam they disagree, though a band contains the point',
      () {
    // The bounds are not the same shape, which is a second difference between
    // the pair and has nothing to do with snapping: `bandIdAt` tests
    // `dy <= bottom` (inclusive) and answers the band ABOVE the seam, while
    // `bandIdNear` tests `dy < bottom` (exclusive), falls through it and
    // answers the band BELOW. A point exactly on the seam sits in a band on
    // either reading, yet the two name different bands — so "they differ only
    // where no band is under the point" is false, and this file used to say it.
    final JetRect header = _layout.bands.firstWhere((b) => b.id == 'hdr').rect;
    final double seam = header.y + header.height; // == the detail band's top
    expect(_layout.bandIdAt(JetOffset(100, seam)), 'hdr');
    expect(_layout.bandIdNear(JetOffset(100, seam)), 'det');
  });
}
