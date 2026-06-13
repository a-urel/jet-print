/// Loads bundled catalog families into the `List<JetFontFamily>` jet_print's
/// font seam (spec 022) consumes.
library;

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:jet_print/jet_print.dart';

import 'google_font_catalog.dart';
import 'google_font_entry.dart';

/// Builds validated [JetFontFamily] objects from the bundled catalog.
///
/// Reads each family's face bytes via [bundle] (defaults to [rootBundle]),
/// groups the faces, and constructs a [JetFontFamily] (which validates the
/// bytes). [only], when given, limits loading to those family names (reduces
/// startup parse cost + memory; it does NOT reduce the app's bundle size — all
/// catalog assets ship with the package). A family whose bytes fail to load or
/// validate is skipped with a logged warning — this never throws mid-load.
///
/// Pass the result to BOTH `JetReportDesigner`/`JetReportWorkspace.fonts` and
/// `RenderOptions.fonts` so the picker and the render chain agree.
Future<List<JetFontFamily>> loadGoogleFonts({
  Iterable<String>? only,
  AssetBundle? bundle,
}) async {
  final AssetBundle assets = bundle ?? rootBundle;
  final Set<String>? wanted = only?.toSet();
  final List<JetFontFamily> families = <JetFontFamily>[];
  for (final GoogleFontEntry entry in googleFontCatalog) {
    if (wanted != null && !wanted.contains(entry.name)) continue;
    try {
      final List<JetFontFace> faces = <JetFontFace>[];
      for (final MapEntry<FontFaceSlot, String> face
          in entry.faceAssets.entries) {
        final ByteData data = await assets.load(face.value);
        final Uint8List bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        faces.add(JetFontFace(
            bytes: bytes, weight: face.key.weight, italic: face.key.italic));
      }
      families.add(JetFontFamily(name: entry.name, faces: faces));
    } catch (error) {
      developer.log('Skipping font "${entry.name}": $error',
          name: 'jet_print_google_fonts');
    }
  }
  return families;
}
