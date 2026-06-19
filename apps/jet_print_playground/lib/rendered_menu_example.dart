/// Real data for the restaurant-menu sample, plus the one-call render through
/// the public engine — the consumer side of the category-grouped picture menu,
/// all through `package:jet_print/jet_print.dart` only.
///
/// Seven dishes across three categories, ordered by category so the group breaks
/// resolve. Each row carries a generated BMP swatch (base64) as its `photo`;
/// the declared schema (`menuSchema.fields`) is passed to the data source so
/// `$F{...}` bindings resolve. The list is `final`, not `const`, because the
/// photo bytes are computed.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'menu_photo.dart';
import 'menu_sample.dart';

/// A 64×64 generated food card as base64 — a warm gradient background with the
/// dish's [icon] glyph on a cream plate. Stands in for a real photo while
/// keeping the sample asset-free.
String _photo(int topRgb, int bottomRgb, FoodIcon icon) => foodBmpBase64(
      width: 64,
      height: 64,
      topRgb: topRgb,
      bottomRgb: bottomRgb,
      icon: icon,
    );

/// The sample menu — the source of truth the data source and the tests both
/// read, so the rendered prices and the expected values can never drift.
final List<Map<String, Object?>> kSampleMenu = <Map<String, Object?>>[
  // --- Appetizers ---
  <String, Object?>{
    'category': 'Appetizers',
    'name': 'Bruschetta',
    'description': 'Grilled sourdough, vine tomato, basil, olive oil.',
    'price': 8.00,
    'photo': _photo(0xE8C07A, 0xB6772E, FoodIcon.bruschetta),
  },
  <String, Object?>{
    'category': 'Appetizers',
    'name': 'Crispy Calamari',
    'description': 'Lightly fried, lemon aioli, sea salt.',
    'price': 11.00,
    'photo': _photo(0xF0D9A8, 0xC79A4B, FoodIcon.calamari),
  },
  // --- Mains ---
  <String, Object?>{
    'category': 'Mains',
    'name': 'Margherita Pizza',
    'description': 'San Marzano tomato, fior di latte, basil.',
    'price': 14.00,
    'photo': _photo(0xE7553B, 0x7E1F12, FoodIcon.pizza),
  },
  <String, Object?>{
    'category': 'Mains',
    'name': 'Spaghetti Carbonara',
    'description': 'Guanciale, pecorino, egg yolk, black pepper.',
    'price': 13.00,
    'photo': _photo(0xF2E2B0, 0xC9A24A, FoodIcon.carbonara),
  },
  <String, Object?>{
    'category': 'Mains',
    'name': 'Grilled Salmon',
    'description': 'Seasonal greens, lemon-dill butter.',
    'price': 19.00,
    'photo': _photo(0xF1A07A, 0xB24A36, FoodIcon.salmon),
  },
  // --- Desserts ---
  <String, Object?>{
    'category': 'Desserts',
    'name': 'Tiramisu',
    'description': 'Espresso-soaked savoiardi, mascarpone, cocoa.',
    'price': 7.00,
    'photo': _photo(0xC9A07A, 0x5E3B22, FoodIcon.tiramisu),
  },
  <String, Object?>{
    'category': 'Desserts',
    'name': 'Pistachio Gelato',
    'description': 'House-churned, Sicilian pistachio.',
    'price': 6.00,
    'photo': _photo(0xCFE0A0, 0x6F8E3C, FoodIcon.gelato),
  },
];

/// The sample menu as an in-memory data source, matching [menuSchema]. The
/// declared `fields:` is passed so `$F{...}` bindings (incl. the photo) resolve.
JetDataSource menuDataSource() =>
    JetInMemoryDataSource(kSampleMenu, fields: menuSchema.fields);

/// Renders [menuSampleDefinition] over [menuDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderMenuDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? menuSampleDefinition(),
      source ?? menuDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(menuSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares (top-level and nested), so all `$F{...}`
/// bindings are recognized.
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
