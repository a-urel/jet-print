# Changelog

## 0.1.0 (unreleased)

- Initial release: curated offline catalog of open-source font families,
  exposed as `loadGoogleFonts()` producing `List<JetFontFamily>` for jet_print.
- `GoogleFontEntry`, `FontFaceSlot`, `googleFontCatalog`, and
  `loadGoogleFonts({only, bundle})`.
- A catalog of 33 families, from Arvo to Work Sans, among them Inter, Roboto,
  Noto Sans, Noto Serif and JetBrains Mono — Latin + Latin-Extended subsets,
  Turkish-covering; `tool/fetch_google_fonts.dart` regenerates it from
  Google Fonts (`tool/curated_families.dart` lists the families).
