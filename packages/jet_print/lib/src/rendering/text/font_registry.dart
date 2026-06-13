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

  /// Registers the bundled default under [defaultFamily]. Pass [bytes] to
  /// override (e.g. tests); otherwise the embedded font is used.
  void registerDefault({Uint8List? bytes}) =>
      register(defaultFamily, bytes ?? kDefaultFontBytes);

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
