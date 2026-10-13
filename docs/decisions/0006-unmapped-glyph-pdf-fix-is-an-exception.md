# 0006 — Exporting an unmapped character as .notdef is an accepted output change in 1.x

**Status:** Accepted — 2026-10-13

## Context

[`0004`](0004-what-1-0-must-settle.md) made the output of an existing report
part of the 1.x contract: for the same definition, data, fonts and platform, a
`1.x` upgrade must not change what a PDF or PNG shows. It anticipated this case
and said how to handle it: "A rendering bug found after `1.0.0` that changes
output has to ship behind an opt-in, such as a `RenderOptions` flag, or wait
for a major version."

Such a bug has been found. PDF export mishandled any character the embedded
font has no glyph for: `∑` or `✓` in the bundled default font, `₺` before
[#124](https://github.com/a-urel/jet-print/pull/124) added it, any emoji, or any
two characters a host font draws with one glyph. dart_pdf gives every distinct
character its own CID and its own slot in the embedded font subset, with CID 0
(U+0000) holding `.notdef`. A second character that resolves to an
already-placed glyph makes its subsetter (`TtfWriter.withChars`) take "the
first remaining glyph" instead:

- when no glyph remains, `JetReportExporter.toPdf`, and with it
  `JetReportPrinter.printReport`, throws `Bad state: No element`;
- otherwise the PDF draws a glyph that belongs to a *different* character, so
  `Toplam ∑ 125,50` exports with some other letter where `∑` was.

Which of the two happens depends on the order dart_pdf meets the characters in
the whole document, not on the text element. So the same report can crash or
export after an unrelated edit elsewhere in it.

The fix, in [#128](https://github.com/a-urel/jet-print/pull/128)
(`rendering/export/pdf_painter.dart` → `PdfPainter._pdfText`), maps each
character to one canonical character per glyph before it reaches dart_pdf, and
a missing one to U+0000. The PDF then draws `.notdef`, the box the engine
measured and laid out. A PDF that contains no such character is byte-for-byte
unchanged, and `test/goldens/invoice.pdf` passes. A PDF that contained one
changes in two ways: where it crashed, it now exports, and where it drew a
borrowed glyph, it now draws `.notdef`.

The first change is outside 0004's promise: a crash is not output. The second is
inside it, and is what this record is about.

## Decision

**The `.notdef` fix ships in a `1.x` minor release, without an opt-in.** It is
an accepted exception to [`0004`](0004-what-1-0-must-settle.md)'s rule 2, and
the changelog entry that ships it names this record.

The test it passes, which a later exception must pass too:

1. **The old output was never what the definition asked for.** It was not a
   rounding, a spacing or a styling choice a host might depend on. It was
   another character's glyph, chosen by subsetter order.
2. **The old output was not stable.** The same character in the same element
   crashed or drew a borrowed glyph depending on the rest of the document, so
   no host could have relied on it.
3. **The new output is what the engine already measured.** The engine
   measures an unmapped character at the `.notdef` advance, so the layout
   already made room for exactly the box the PDF now draws. This is a claim
   about the PDF only: the canvas and preview draw through Flutter, which may
   fall back to a platform font (see *What this does not decide*).
4. **Output that was correct does not move.** A PDF without such a character is
   byte-for-byte identical, which a golden pins.

An opt-in was rejected. Its default would have to keep both behaviours, the
crash and the borrowed glyph, and a host would have to discover a flag in order
to stop its exports from crashing.

## Consequences

**Two kinds of change to an existing PDF.** One that crashed now exports, and
one that showed a wrong letter now shows a box. Neither can be told apart from
a fix by a host that compared bytes. The changelog says which reports are
affected: those containing a character their font lacks, or two characters
their font draws alike.

**Text extraction changes for those characters.** The character handed to
dart_pdf is now U+0000 for a missing character, or the canonical character for
a shared glyph, such as a space for a no-break space; dart_pdf writes its
ToUnicode entry from that character. So a PDF reader copying the text should
get those characters where it used to get the original one, drawn with the
wrong glyph. The tests pin the CID emitted for a missing character, not what a
reader extracts from it, and no test uses a font with a shared glyph: the
shared-glyph case follows from the same mapping, unexercised.

**0004 now has a recorded exception, and with it a precedent.** That is the
cost. Its rule is weaker for having one, and the four-part test above exists so
the next case is argued against something specific, not against "this one was
also obviously a bug". A change that fails any part of it goes behind an opt-in
or waits for `2.0`, exactly as 0004 says.

## What this does not decide

- **Any other output change.** This record accepts one fix. It does not relax
  rule 2 for bugs in general.
- **What the canvas and preview show for a missing character.** They draw
  through Flutter, whose text stack may fall back to a platform font. Whether
  that should be suppressed, so that every surface shows `.notdef`, is a
  separate question about the one-paint-path rule.
- **Whether to warn.** Render reports no diagnostic for a character its font
  lacks. Adding one would change the diagnostics a render reports, which 0004
  also counts as output.
