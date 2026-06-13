# Changelog

## 0.1.0 (unreleased)

- Initial release: curated offline catalog of open-source font families,
  exposed as `loadGoogleFonts()` producing `List<JetFontFamily>` for jet_print.
- `GoogleFontEntry`, `googleFontCatalog`, and `loadGoogleFonts({only, bundle})`.
- Seed catalog (Noto Sans, Noto Serif, JetBrains Mono — Latin+Ext subsets,
  Turkish-covering); `tool/fetch_google_fonts.dart` grows it from Google Fonts.
