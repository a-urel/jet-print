Roll paper for receipt and kitchen-ticket printers, the Turkish lira sign in the bundled font, a currency symbol for `¤`, and a PDF export fix for characters a font lacks. A minor release under the `1.0.0` freeze: everything is additive except the one output change under *Fixed*, accepted by decision 0006. One optional page key is new, and only a report that sets it is written at schema version 3; every other report is written at version 2, as before (see *Compatibility*).

```sh
flutter pub upgrade jet_print
```

[pub.dev](https://pub.dev/packages/jet_print/versions/1.1.0) · [Changelog](https://github.com/a-urel/jet-print/blob/jet_print-v1.1.0/packages/jet_print/CHANGELOG.md)

## Added

- **The default font draws the Turkish lira sign.** `₺` (U+20BA) is now in all four faces of the bundled font, so a price such as `125,50 ₺` prints on the canvas, in the preview and in PDF and PNG exports, rather than as a tofu box. Before, a text element ending in `₺` made PDF export throw. The glyph was appended to the existing Noto Sans 2.015 subsets, and every glyph that was already there is byte-for-byte unchanged, so existing reports render exactly as before. `tool/fonts/add_glyphs.py` adds a codepoint the same way. The package grows by about 0.5 KB.

- **`RenderOptions.currencySymbol` sets what `¤` prints.** By default `¤` in a number pattern prints the ISO code of the render locale's currency, so the designer's *Currency* preset `¤#,##0.00` shows `TRY1.234,50` under `Locale('tr')`. That stays the default, because changing it would change what existing reports print. Pass `currencySymbol: '₺'` to print `₺1.234,50` instead, in the format property and in `FORMAT(...)` alike, page headers and footers included. Only the sign changes: the pattern still sets the decimal digits (`#,##0 ¤` is `1.235 ₺`), and the locale still sets the separators.

- **Roll paper: pages that fit their content.** `PageFormat.continuous` lays a report out for a receipt or kitchen-ticket printer. A continuous page never breaks because it is full: each rendered page is as tall as its header, body, footer and margins, and `height` becomes the shortest a page may be. The page footer follows the content instead of sitting at a fixed bottom. A group that starts a new page still does, so one report grouped by station prints one ticket per station, each cut to its own length. `keepTogether` has nothing to do on a roll, and a label grid lays every label on one page. The preview, PDF, PNG and print all take each page's height from the same frame, so a 203 dpi PNG for an ESC/POS printer is `pageToPng(report, i, scale: 203 / 72)`. A page taller than 14,400 pt, the size many PDF readers refuse, still renders, with a warning.

- **The designer offers roll paper.** The page section has a *Continuous (roll) page* switch, and the paper picker lists *Roll 58 mm* and *Roll 80 mm* after the sheet sizes, with a 50 mm minimum height. Picking a roll turns the switch on, and picking a sheet size turns it off. A roll has no landscape, so the orientation toggle is hidden on one. English, German and Turkish strings are included.

## Changed

- **The designer is no longer claimed on Android and iOS.** The README now says that, on a phone or tablet, rendering, export, printing and `JetReportPreview` are supported, while `JetReportDesigner` and `JetReportWorkspace` run and are tested at phone width but are not yet verified on a real device. Nothing in the code changes. The `1.0.0` entry below says that version would be published only once that device pass was recorded; it was published without it, and [decision 0005](https://github.com/a-urel/jet-print/blob/main/docs/decisions/0005-mobile-designer-claim-narrowed.md) narrows the claim accordingly.

- **The preview's thumbnail rail fits a taller page into its tile.** Tiles still take their height from page 0. A later page that is taller, as a continuous report's longer ticket can be, is scaled down to fit its tile, keeping its proportions, instead of overflowing it. Reports whose pages are all one size look exactly as before.

## Fixed

- **PDF export no longer fails on a character the font cannot draw.** A text whose last new character had no glyph in its font, such as `∑` or `✓` in the bundled default font, made `JetReportExporter.toPdf` throw `Bad state: No element`. When the character came earlier in the text the export succeeded but was garbled, with later characters drawn with another character's shape. Such a character now exports as the font's missing-glyph box (`.notdef`), at the width the layout gave it, and the rest of the text is drawn correctly. Copying the box's text out of the PDF yields U+0000. A tab is drawn as the space the layout measured it as. In a font that draws several characters with one shape, such as a space and a no-break space, copied text gives the lowest of them for each, whichever came first. A PDF with none of these characters draws exactly as before; its bytes change only in the width its fonts list for `.notdef`, which such a PDF never draws. A PDF that drew a borrowed glyph now draws `.notdef` in its place. That is a change in output under [decision 0004](https://github.com/a-urel/jet-print/blob/main/docs/decisions/0004-what-1-0-must-settle.md), accepted as an exception by [decision 0006](https://github.com/a-urel/jet-print/blob/main/docs/decisions/0006-unmapped-glyph-pdf-fix-is-an-exception.md): the old output was never the character asked for, and was not even stable.

## Compatibility

- **A roll-paper report is written at schema version 3; every other report is still written at version 2.** A continuous page writes `"continuous": true` in the page JSON and stamps the document `"schemaVersion": 3`. A sheet report writes neither, so its JSON is byte-for-byte unchanged and `1.0.0` keeps opening it. `1.0.0` refuses a roll report with a `ReportFormatException` (its version is newer), rather than opening it as a sheet and dropping the roll when it saves. `JetReportFormat.schemaVersion` is now `3`: the newest version this build reads and writes, not one every document carries. A host that stores the stamped version should read it from each document.

**Full changelog:** [`1.0.0...1.1.0`](https://github.com/a-urel/jet-print/compare/jet_print-v1.0.0...jet_print-v1.1.0)
