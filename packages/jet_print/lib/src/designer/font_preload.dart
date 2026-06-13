// lib/src/designer/font_preload.dart
/// Preloads registry families into the Flutter engine for the designer UI.
/// Lives in the designer layer (not rendering/text) because it talks to
/// `dart:ui` — the rendering engine stays headless outside its two declared
/// paint backends.
library;

import 'dart:ui' as ui;

import '../domain/styles/text_style.dart';
import '../rendering/paint/canvas_painter.dart' show FontLoader;
import '../rendering/text/font_registry.dart';
import '../rendering/text/ui_font_family.dart';

/// Loads the Regular face of every family in [registry] into the Flutter
/// engine under its [uiFontFamily] name, so the family picker's own-typeface
/// option previews render correctly before the canvas has ever painted that
/// family. (The canvas painter still loads the exact variants it uses,
/// lazily; already-loaded names are simply re-registered by the engine.)
Future<void> preloadUiFontFamilies(
  FontRegistry registry, {
  FontLoader? fontLoader,
}) async {
  final FontLoader load = fontLoader ?? ui.loadFontFromList;
  for (final String family in registry.families) {
    await load(registry.bytesFor(family),
        fontFamily: uiFontFamily(family, JetFontWeight.normal, false));
  }
}
