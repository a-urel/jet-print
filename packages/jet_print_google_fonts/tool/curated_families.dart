/// Families the catalog bundles. Each must have Regular/Bold/Italic/BoldItalic
/// on Google Fonts. Edit this list to grow/shrink the catalog, then run
/// `dart run tool/fetch_google_fonts.dart`.
library;

/// (family display name, license id, Google Fonts CSS family token).
const List<(String, String, String)> curatedFamilies =
    <(String, String, String)>[
  ('Roboto', 'Apache-2.0', 'Roboto'),
  ('Open Sans', 'OFL-1.1', 'Open+Sans'),
  ('Lato', 'OFL-1.1', 'Lato'),
  ('Montserrat', 'OFL-1.1', 'Montserrat'),
  ('Lora', 'OFL-1.1', 'Lora'),
  ('Merriweather', 'OFL-1.1', 'Merriweather'),
  ('Inter', 'OFL-1.1', 'Inter'),
  ('Source Sans 3', 'OFL-1.1', 'Source+Sans+3'),
  ('Nunito', 'OFL-1.1', 'Nunito'),
  ('Work Sans', 'OFL-1.1', 'Work+Sans'),
  // … extend to ~60. Keep families that publish all four faces.
];
