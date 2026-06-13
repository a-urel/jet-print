/// Families the catalog bundles. Faces that exist on Google Fonts
/// (Regular/Bold/Italic/BoldItalic) are fetched; missing faces are skipped and
/// fall back to Regular at render time. Edit this list to grow/shrink the
/// catalog, then run `dart run tool/fetch_google_fonts.dart`.
library;

/// (family display name, license id, Google Fonts CSS family token).
const List<(String, String, String)> curatedFamilies =
    <(String, String, String)>[
  ('Roboto', 'Apache-2.0', 'Roboto'),
  ('Open Sans', 'OFL-1.1', 'Open+Sans'),
  ('Lato', 'OFL-1.1', 'Lato'),
  ('Montserrat', 'OFL-1.1', 'Montserrat'),
  ('Poppins', 'OFL-1.1', 'Poppins'),
  ('Raleway', 'OFL-1.1', 'Raleway'),
  ('Inter', 'OFL-1.1', 'Inter'),
  ('Nunito', 'OFL-1.1', 'Nunito'),
  ('Work Sans', 'OFL-1.1', 'Work+Sans'),
  ('Rubik', 'OFL-1.1', 'Rubik'),
  ('Mulish', 'OFL-1.1', 'Mulish'),
  ('Karla', 'OFL-1.1', 'Karla'),
  ('DM Sans', 'OFL-1.1', 'DM+Sans'),
  ('Manrope', 'OFL-1.1', 'Manrope'),
  ('Barlow', 'OFL-1.1', 'Barlow'),
  ('Libre Franklin', 'OFL-1.1', 'Libre+Franklin'),
  ('Fira Sans', 'OFL-1.1', 'Fira+Sans'),
  ('Cabin', 'OFL-1.1', 'Cabin'),
  ('Source Sans 3', 'OFL-1.1', 'Source+Sans+3'),
  ('Lora', 'OFL-1.1', 'Lora'),
  ('Merriweather', 'OFL-1.1', 'Merriweather'),
  ('Playfair Display', 'OFL-1.1', 'Playfair+Display'),
  ('PT Serif', 'OFL-1.1', 'PT+Serif'),
  ('Bitter', 'OFL-1.1', 'Bitter'),
  ('EB Garamond', 'OFL-1.1', 'EB+Garamond'),
  ('Libre Baskerville', 'OFL-1.1', 'Libre+Baskerville'),
  ('Crimson Text', 'OFL-1.1', 'Crimson+Text'),
  ('Spectral', 'OFL-1.1', 'Spectral'),
  ('Roboto Slab', 'Apache-2.0', 'Roboto+Slab'),
  ('Arvo', 'OFL-1.1', 'Arvo'),
];
