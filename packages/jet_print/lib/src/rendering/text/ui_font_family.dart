// lib/src/rendering/text/ui_font_family.dart
/// The engine font-family naming convention for registry variants, shared by
/// the canvas painter (which loads variant bytes under these names) and the
/// designer's family picker (whose option previews fall back to them). Pure
/// string math — the actual engine loading lives with the dart:ui importers.
library;

import '../../domain/styles/text_style.dart';

/// A `dart:ui` family name unique to the (family, weight, italic) variant, so
/// distinct variant bytes never collide under one name.
String uiFontFamily(String family, JetFontWeight weight, bool italic) =>
    '${family}__${weight.name}${italic ? '_italic' : ''}';
