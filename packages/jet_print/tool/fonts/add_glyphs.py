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
            k: v
            for k, v in vars(font["hhea"]).items()
            if k not in ("numberOfHMetrics", "advanceWidthMax")
        },
        "head": {
            k: v for k, v in vars(font["head"]).items() if k != "checkSumAdjustment"
        },
        "upem": font["head"].unitsPerEm,
    }


def append(subset_path, source_path, codepoints):
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
        for table in cmap_tables:
            table.cmap[cp] = name
        added.append(name)

    if not added:
        return
    subset["maxp"].numGlyphs = len(subset.getGlyphOrder())

    # The claim: nothing that existed moved.
    after = snapshot(subset)
    n = len(before["order"])
    assert after["order"][:n] == before["order"], "glyph order changed"
    for key in ("hhea", "upem", "head"):
        assert after[key] == before[key], f"{key} changed"
    for g in before["order"]:
        assert after["hmtx"][g] == before["hmtx"][g], f"advance of {g} changed"
        assert after["outlines"][g] == before["outlines"][g], f"{g} changed"
    for cp, g in before["cmap"].items():
        assert after["cmap"][cp] == g, f"U+{cp:04X} remapped"
    for name in added:
        cp = int(name[3:], 16)
        src = source.getBestCmap()[cp]
        assert after["outlines"][name] == outline(source, src), name

    subset.save(subset_path)
    print(f"  {os.path.basename(subset_path)}: appended {', '.join(added)}")


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    source_dir = argv[1]
    codepoints = [int(a.upper().removeprefix("U+"), 16) for a in argv[2:]]
    for subset_name, source_name in FACES:
        append(
            os.path.join(HERE, subset_name),
            os.path.join(source_dir, source_name),
            codepoints,
        )


if __name__ == "__main__":
    main(sys.argv)
