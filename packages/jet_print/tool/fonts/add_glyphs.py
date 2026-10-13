#!/usr/bin/env python3
"""Appends glyphs from Noto Sans to the committed default-font subsets.

The four `NotoSans*-subset.ttf` files next to this script were cut from the
Noto Sans 2.015 static faces:

  https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v2.015/NotoSans-v2.015.zip
  (NotoSans/hinted/ttf/NotoSans-{Regular,Bold,Italic,BoldItalic}.ttf)

Re-cutting a subset from scratch could renumber or reshape glyphs every
existing report already draws, and the goldens that would notice are macOS
only. So this script never re-cuts: it APPENDS each requested codepoint's glyph
to the end of the glyph order, decomposed and without hinting (the subsets carry
none), and leaves every existing glyph, glyph id, advance and table it does not
need to touch exactly as it was. It then checks that claim before writing.

Usage, from packages/jet_print, with fontTools installed (`pip install
fonttools`) and the release zip extracted to SRC:

  python3 tool/fonts/add_glyphs.py SRC/NotoSans/hinted/ttf U+20BA
  dart run tool/generate_default_font.dart

then add the codepoints to the list in tool/generate_default_font.dart.
"""

import os
import sys

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))

# Font-wide limits that may only grow when a glyph is appended: they bound
# every glyph, so a new glyph outside them widens them, and one inside (₺ in
# all four faces) leaves them exactly as they were.
_HEAD_BOUNDS = ("xMin", "yMin", "xMax", "yMax")
_HHEA_LIMITS = (
    "numberOfHMetrics",
    "advanceWidthMax",
    "minLeftSideBearing",
    "minRightSideBearing",
    "xMaxExtent",
)

# (committed subset, Noto Sans 2.015 source face)
FACES = [
    ("NotoSans-subset.ttf", "NotoSans-Regular.ttf"),
    ("NotoSans-Bold-subset.ttf", "NotoSans-Bold.ttf"),
    ("NotoSans-Italic-subset.ttf", "NotoSans-Italic.ttf"),
    ("NotoSans-BoldItalic-subset.ttf", "NotoSans-BoldItalic.ttf"),
]


def outline(font, glyph_name):
    pen = DecomposingRecordingPen(font.getGlyphSet())
    font.getGlyphSet()[glyph_name].draw(pen)
    return pen.value


def snapshot(font):
    """Everything an existing glyph is drawn and measured from."""
    order = font.getGlyphOrder()
    return {
        "order": list(order),
        "cmap": dict(font.getBestCmap()),
        "hmtx": {g: font["hmtx"][g] for g in order},
        "outlines": {g: outline(font, g) for g in order},
        "hhea": {
            k: v for k, v in vars(font["hhea"]).items() if k not in _HHEA_LIMITS
        },
        "head": {
            k: v
            for k, v in vars(font["head"]).items()
            if k != "checkSumAdjustment" and k not in _HEAD_BOUNDS
        },
        "upem": font["head"].unitsPerEm,
        "bounds": tuple(getattr(font["head"], k) for k in _HEAD_BOUNDS),
    }


def widen_limits(font, glyph, advance):
    """Grows the font-wide limits a new glyph falls outside, and only those."""
    head, hhea, maxp = font["head"], font["hhea"], font["maxp"]
    hhea.advanceWidthMax = max(hhea.advanceWidthMax, advance)
    if glyph.numberOfContours == 0:
        return  # an empty glyph has no outline to bound
    head.xMin = min(head.xMin, glyph.xMin)
    head.yMin = min(head.yMin, glyph.yMin)
    head.xMax = max(head.xMax, glyph.xMax)
    head.yMax = max(head.yMax, glyph.yMax)
    hhea.minLeftSideBearing = min(hhea.minLeftSideBearing, glyph.xMin)
    hhea.minRightSideBearing = min(hhea.minRightSideBearing, advance - glyph.xMax)
    hhea.xMaxExtent = max(hhea.xMaxExtent, glyph.xMax)
    coords, end_points, _ = glyph.getCoordinates(font["glyf"])
    maxp.maxPoints = max(maxp.maxPoints, len(coords))
    maxp.maxContours = max(maxp.maxContours, len(end_points))


def append(subset_path, source_path, codepoints):
    """Returns the subset with [codepoints] appended, unsaved, or None when it
    already had them all. Exits, writing nothing, if the source lacks one."""
    # No recalculation on save: the font-wide bounding box in `head` and the
    # extents in `hhea` stay the values the subsets were cut with (the PDF
    # FontBBox is read from them), and so does the timestamp, so re-running
    # the script on the same input writes the same bytes.
    subset = TTFont(subset_path, recalcBBoxes=False, recalcTimestamp=False)
    source = TTFont(source_path)
    before = snapshot(subset)
    source_cmap = source.getBestCmap()
    cmap_tables = [t for t in subset["cmap"].tables if t.isUnicode()]

    added = []
    for cp in codepoints:
        if cp in before["cmap"]:
            print(f"  U+{cp:04X} already present, skipped")
            continue
        if cp not in source_cmap:
            sys.exit(f"{os.path.basename(source_path)} has no U+{cp:04X}")
        src_name = source_cmap[cp]
        name = f"uni{cp:04X}"
        pen = TTGlyphPen(None)
        rec = DecomposingRecordingPen(source.getGlyphSet())
        source.getGlyphSet()[src_name].draw(rec)
        rec.replay(pen)
        glyph = pen.glyph()
        subset["glyf"][name] = glyph  # also appends to the glyph order
        glyph.recalcBounds(subset["glyf"])  # only the new glyph's own box
        subset["hmtx"][name] = source["hmtx"][src_name]
        widen_limits(subset, glyph, source["hmtx"][src_name][0])
        for table in cmap_tables:
            table.cmap[cp] = name
        added.append(name)

    if not added:
        return None
    subset["maxp"].numGlyphs = len(subset.getGlyphOrder())

    # The claim: nothing that existed moved.
    after = snapshot(subset)
    n = len(before["order"])
    assert after["order"][:n] == before["order"], "glyph order changed"
    for key in ("hhea", "upem", "head"):
        assert after[key] == before[key], f"{key} changed"
    old, new = before["bounds"], after["bounds"]
    assert new[0] <= old[0] and new[1] <= old[1], "head bounds shrank"
    assert new[2] >= old[2] and new[3] >= old[3], "head bounds shrank"
    for g in before["order"]:
        assert after["hmtx"][g] == before["hmtx"][g], f"advance of {g} changed"
        assert after["outlines"][g] == before["outlines"][g], f"{g} changed"
    for cp, g in before["cmap"].items():
        assert after["cmap"][cp] == g, f"U+{cp:04X} remapped"
    for name in added:
        cp = int(name[3:], 16)
        src = source.getBestCmap()[cp]
        assert after["outlines"][name] == outline(source, src), name

    print(f"  {os.path.basename(subset_path)}: appending {', '.join(added)}")
    return subset


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    source_dir = argv[1]
    codepoints = [int(a.upper().removeprefix("U+"), 16) for a in argv[2:]]
    for cp in codepoints:
        # The engine's TTF reader (lib/src/rendering/text/ttf/ttf_metrics.dart)
        # reads only BMP cmaps, so a glyph past U+FFFF could never be used.
        if cp > 0xFFFF:
            sys.exit(f"U+{cp:04X} is outside the BMP; the runtime cannot map it")
    # Every face is built and checked before any is written, so a face that
    # fails leaves all four subsets as they were: they stay in step.
    staged = []
    for subset_name, source_name in FACES:
        path = os.path.join(HERE, subset_name)
        font = append(path, os.path.join(source_dir, source_name), codepoints)
        if font is not None:
            staged.append((font, path))
    for font, path in staged:
        font.save(path)
    print(f"wrote {len(staged)} of {len(FACES)} subsets")


if __name__ == "__main__":
    main(sys.argv)
