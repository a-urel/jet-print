// lib/src/rendering/text/font_registry.dart
/// Holds registered font bytes keyed by family/weight/italic (spec 006). The
/// bundled default is just a pre-registered entry; the SAME bytes drive
/// measurement (parsed to [FontMetrics]) and painting (loaded by backends).
library;

import 'dart:typed_data';

import '../../domain/styles/text_style.dart';
import 'font_metrics.dart';
import 'fonts/default_font_data.dart';
import 'ttf/ttf_metrics.dart';

/// A registry of font variants. Byte-oriented and headless.
class FontRegistry {
  final Map<String, _FontEntry> _entries = <String, _FontEntry>{};

  /// The family the bundled default registers under.
  static const String defaultFamily = 'JetSans';

  /// The bundled serif family (Noto Serif subset).
  static const String serifFamily = 'JetSerif';

  /// The bundled monospaced family (JetBrains Mono subset).
  static const String monoFamily = 'JetMono';

  /// Registers [bytes] for [family]/[weight]/[italic], parsing its metrics now.
  void register(
    String family,
    Uint8List bytes, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) {
    _entries[_key(family, weight, italic)] =
        _FontEntry(bytes, parseTtfMetrics(bytes));
  }

  /// Registers the bundled fonts: [defaultFamily] (Noto Sans), [serifFamily]
  /// (Noto Serif), and [monoFamily] (JetBrains Mono), each in all four
  /// embedded faces (Regular, Bold, Italic, Bold Italic) — so a family or
  /// Bold/Italic edit changes glyphs everywhere this registry feeds: canvas,
  /// preview, and export alike. Intermediate weights (`medium`/`semiBold`)
  /// have no bundled face and resolve to Regular via the fallback chain.
  ///
  /// Pass [bytes] to override with a single Regular face under
  /// [defaultFamily] (the test seam); no other face or family is then
  /// registered and every lookup falls back to the override.
  void registerDefault({Uint8List? bytes}) {
    if (bytes != null) {
      register(defaultFamily, bytes);
      return;
    }
    register(defaultFamily, kDefaultFontBytes);
    register(defaultFamily, kDefaultFontBoldBytes, weight: JetFontWeight.bold);
    register(defaultFamily, kDefaultFontItalicBytes, italic: true);
    register(defaultFamily, kDefaultFontBoldItalicBytes,
        weight: JetFontWeight.bold, italic: true);
    register(serifFamily, kSerifFontBytes);
    register(serifFamily, kSerifFontBoldBytes, weight: JetFontWeight.bold);
    register(serifFamily, kSerifFontItalicBytes, italic: true);
    register(serifFamily, kSerifFontBoldItalicBytes,
        weight: JetFontWeight.bold, italic: true);
    register(monoFamily, kMonoFontBytes);
    register(monoFamily, kMonoFontBoldBytes, weight: JetFontWeight.bold);
    register(monoFamily, kMonoFontItalicBytes, italic: true);
    register(monoFamily, kMonoFontBoldItalicBytes,
        weight: JetFontWeight.bold, italic: true);
  }

  /// Whether the default font has been registered.
  bool get hasDefault =>
      _entries.containsKey(_key(defaultFamily, JetFontWeight.normal, false));

  /// Registered family names: [defaultFamily] first (when registered), then
  /// the rest in insertion order, deduped across weight/italic variants — the
  /// designer's family picker enumerates exactly this list (021 / FR-001).
  List<String> get families {
    final List<String> result = <String>[];
    for (final String key in _entries.keys) {
      final String family = key.substring(0, key.indexOf('|'));
      if (!result.contains(family)) result.add(family);
    }
    if (result.remove(defaultFamily)) result.insert(0, defaultFamily);
    return result;
  }

  /// Metrics for the resolved variant (falls back to the default).
  FontMetrics metricsFor(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) =>
      _resolve(family, weight, italic).metrics;

  /// Raw bytes for the resolved variant (for backends to embed/load).
  Uint8List bytesFor(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) =>
      _resolve(family, weight, italic).bytes;

  /// The family name a backend should render with after fallback.
  String resolveFamily(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) {
    if (family != null &&
        (_entries.containsKey(_key(family, weight, italic)) ||
            _entries.containsKey(_key(family, weight, false)) ||
            _entries.containsKey(_key(family, JetFontWeight.normal, false)))) {
      return family;
    }
    return defaultFamily;
  }

  _FontEntry _resolve(String? family, JetFontWeight weight, bool italic) {
    final String fam = family ?? defaultFamily;
    final _FontEntry? entry = _entries[_key(fam, weight, italic)] ??
        _entries[_key(fam, weight, false)] ??
        _entries[_key(fam, JetFontWeight.normal, false)] ??
        _entries[_key(defaultFamily, JetFontWeight.normal, false)];
    if (entry == null) {
      throw StateError(
          'No font registered for "$fam" and no default; call registerDefault().');
    }
    return entry;
  }

  static String _key(String family, JetFontWeight weight, bool italic) =>
      '$family|${weight.name}|$italic';
}

class _FontEntry {
  _FontEntry(this.bytes, this.metrics);
  final Uint8List bytes;
  final FontMetrics metrics;
}
