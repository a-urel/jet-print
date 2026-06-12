/// Margin quick-picks for the PAGE section (018) — a private designer-layer
/// catalog mirroring `paper_presets.dart`. A preset writes the same value to all
/// four sides; the chosen value is the only thing that reaches the model. Preset
/// identity is **derived for display, never persisted**.
library;

import '../domain/geometry.dart';

/// Which margin preset a value matches. The localized display name is resolved
/// at the call site (the panel), keeping this catalog l10n-free.
enum MarginPresetKind {
  /// The ~1 cm default on every side (matches existing templates).
  normal,

  /// ~0.5 cm on every side.
  narrow,

  /// ~2 cm on every side.
  wide,

  /// Zero margins, flush to the page edge.
  none,
}

/// A named margin preset: a [kind] and the per-side [value] (points) it writes.
class MarginPreset {
  /// Creates a preset of [kind] applying [value] to all four sides.
  const MarginPreset(this.kind, this.value);

  /// The preset's identity (its localized label is resolved by the panel).
  final MarginPresetKind kind;

  /// The per-side margin this preset applies, in points.
  final double value;
}

/// The margin presets offered by the picker, in display order (research D2).
/// `Normal` equals the existing default, so pre-feature templates read as Normal
/// rather than Custom.
const List<MarginPreset> kMarginPresets = <MarginPreset>[
  MarginPreset(MarginPresetKind.normal, 28.35),
  MarginPreset(MarginPresetKind.narrow, 14.17),
  MarginPreset(MarginPresetKind.wide, 56.69),
  MarginPreset(MarginPresetKind.none, 0),
];

/// The result of [recognizeMargin]: either a named [kind] match or [isCustom].
class MarginMatch {
  /// A match against the preset [kind].
  const MarginMatch.preset(MarginPresetKind kind) : _kind = kind;

  /// No preset matched — the margins are custom (uneven, or an off-preset value).
  const MarginMatch.custom() : _kind = null;

  final MarginPresetKind? _kind;

  /// The matched preset's kind, or null when [isCustom].
  MarginPresetKind? get kind => _kind;

  /// Whether the margins match no preset.
  bool get isCustom => _kind == null;
}

/// The half-point tolerance recognition allows, so margins rounded to whole
/// points (a panel shows `28`, the model holds `28.35`) still name their preset
/// (the recognition truth table). The presets are far enough apart to stay
/// distinct.
const double _kMarginTolerance = 0.5;

/// Names [margins] by the preset all four equal sides match, or reports
/// [MarginMatch.isCustom] when the sides are uneven or match no preset value.
/// Pure and display-only — it never rewrites the margins.
MarginMatch recognizeMargin(JetEdgeInsets margins) {
  final bool equalSides =
      (margins.left - margins.top).abs() <= _kMarginTolerance &&
          (margins.left - margins.right).abs() <= _kMarginTolerance &&
          (margins.left - margins.bottom).abs() <= _kMarginTolerance;
  if (equalSides) {
    for (final MarginPreset preset in kMarginPresets) {
      if ((margins.left - preset.value).abs() <= _kMarginTolerance) {
        return MarginMatch.preset(preset.kind);
      }
    }
  }
  return const MarginMatch.custom();
}
