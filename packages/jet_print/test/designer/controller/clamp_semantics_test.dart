// `clampToBand` and `clampResizeToBand` are a lookalike pair, and the whole
// reason both exist is that they answer an overflowing rect DIFFERENTLY:
//
//   * `clampToBand` (controller/element_bounds.dart) is MOVE-style — it keeps
//     the size and slides the rect back inside the band.
//   * `clampResizeToBand` (canvas/resize_handle.dart) is EDGE-style — it pins
//     only the edges the dragged handle moves and leaves the anchored edges
//     where they are, so a handle stopped at a border simply stops.
//
// Two comments claimed `clampToBand` was the single clamp authority for every
// geometry command. It is not: a live move clamps its DELTA inline in
// `_clampedMoveTargets`, and an interactive resize clamps through
// `clampResizeToBand` and commits that preview verbatim — neither touches
// `clampToBand`, which serves the committed/numeric paths (create, paste,
// set-geometry, `resizeTo`, `_commitBounds`). The behavioural difference the
// comments erased is pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/resize_handle.dart';
import 'package:jet_print/src/designer/controller/element_bounds.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

// Round numbers on purpose: a 200x100 content box, so every expectation below
// is readable arithmetic rather than A4 points.
const PageFormat _page =
    PageFormat(width: 200, height: 400, margins: JetEdgeInsets.all(0));
const Band _band = Band(id: 'b', type: BandType.detail, height: 100);

/// 40 wide, its right edge 20pt past the band's right border.
const JetRect _overRight = JetRect(x: 180, y: 0, width: 40, height: 20);

/// 60 wide, its left edge 30pt before the band's left border.
const JetRect _overLeft = JetRect(x: -30, y: 0, width: 60, height: 20);

JetRect _resize(JetRect r, ResizeHandle h) =>
    clampResizeToBand(r, h, bandContentWidth(_page), _band.height);

void main() {
  group('clampToBand — move-style: keep the size, slide the rect', () {
    test('an element past the right border slides left, same width', () {
      // Fails if `clampToBand` ever truncates the overflowing edge instead of
      // sliding — i.e. if it were replaced by resize semantics.
      expect(clampToBand(_overRight, _band, _page),
          const JetRect(x: 160, y: 0, width: 40, height: 20));
    });

    test('an element past the left border slides right, same width', () {
      expect(clampToBand(_overLeft, _band, _page),
          const JetRect(x: 0, y: 0, width: 60, height: 20));
    });

    test('an element wider than the band shrinks rather than sliding off', () {
      // Size is clamped before position, so an oversized element fits instead
      // of being pushed out of view.
      expect(
          clampToBand(
              const JetRect(x: 50, y: 0, width: 300, height: 20), _band, _page),
          const JetRect(x: 0, y: 0, width: 200, height: 20));
    });
  });

  group('clampResizeToBand — edge-style: pin the dragged edge only', () {
    test('a right-handle drag past the border shrinks, leaving x put', () {
      // Fails if the anchored left edge is ever allowed to move — the exact
      // bug that using `clampToBand` for a resize would reintroduce.
      expect(_resize(_overRight, ResizeHandle.right),
          const JetRect(x: 180, y: 0, width: 20, height: 20));
    });

    test(
        'a left-handle drag past the border shrinks, leaving the right edge put',
        () {
      expect(_resize(_overLeft, ResizeHandle.left),
          const JetRect(x: 0, y: 0, width: 30, height: 20));
    });

    test('a handle that does not move the overflowing edge leaves it alone',
        () {
      // `top` moves neither the left nor the right edge, so the horizontal
      // overflow is not this handle's business and is passed through.
      expect(_resize(_overRight, ResizeHandle.top), _overRight);
    });
  });

  test('the two clamps disagree on the same overflowing rect', () {
    // The property the stale comments erased by calling `clampToBand` the
    // single authority. Same input, same band, two different answers.
    final JetRect moved = clampToBand(_overRight, _band, _page);
    final JetRect resized = _resize(_overRight, ResizeHandle.right);
    expect(moved, isNot(resized));
    expect(moved.width, _overRight.width, reason: 'move keeps the size');
    expect(resized.x, _overRight.x, reason: 'resize keeps the anchored edge');
  });
}
