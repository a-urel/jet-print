/// A curated, offline catalog of open-source (Google Fonts) families for
/// jet_print. Bundles subset faces as assets and builds the
/// `List<JetFontFamily>` jet_print's font seam consumes (spec 022).
///
/// ```dart
/// final fonts = await loadGoogleFonts();
/// JetReportWorkspace(fonts: fonts, renderReport: (t) =>
///     engine.render(t, data, options: RenderOptions(fonts: fonts)));
/// ```
library;

export 'src/google_font_catalog.dart' show googleFontCatalog;
export 'src/google_font_entry.dart' show FontFaceSlot, GoogleFontEntry;
export 'src/google_fonts_loader.dart' show loadGoogleFonts;
