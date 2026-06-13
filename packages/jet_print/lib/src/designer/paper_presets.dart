/// Standard paper-size quick-picks for the PAGE section (018) — a private
/// designer-layer catalog, mirroring `format_presets.dart`. Only the resulting
/// [PageFormat] ever reaches the model; the preset identity (the name "A4",
/// "Letter", …) is **derived for display, never persisted**.
library;

import '../domain/geometry.dart';
import '../domain/page_format.dart';

/// A named standard paper size, stored **portrait** (width ≤ height). The
/// landscape variant is derived by swapping the two dimensions.
class PaperPreset {
  /// Creates a preset named [name] with the given portrait dimensions (points).
  const PaperPreset(this.name, this.portraitWidth, this.portraitHeight);

  /// The universal size name (e.g. `'A4'`, `'Letter'`) — **not** localized: it
  /// is an international standard, like a unit symbol (research D1).
  final String name;

  /// Portrait width, in points (the shorter side).
  final double portraitWidth;

  /// Portrait height, in points (the longer side).
  final double portraitHeight;
}

/// The standard sizes offered by the paper-type picker, in display order, stored
/// portrait (research D1). A4 matches [PageFormat.a4Portrait] exactly; A3/A5 are
/// ISO 216; Letter/Legal are ANSI at 72 pt/inch.
const List<PaperPreset> kPaperPresets = <PaperPreset>[
  PaperPreset('A4', 595.28, 841.89),
  PaperPreset('A3', 841.89, 1190.55),
  PaperPreset('A5', 419.53, 595.28),
  PaperPreset('Letter', 612.0, 792.0),
  PaperPreset('Legal', 612.0, 1008.0),
];

/// A preset's display label: its universal name plus its size in whole
/// millimetres, e.g. `A4 (210 × 297 mm)`. Points convert at 25.4/72 mm/pt and
/// round to whole millimetres (standard sizes are whole-mm by definition; ANSI
/// sizes round cleanly too). The name stays unlocalized; mm is a universal unit.
String paperPresetLabel(PaperPreset p) =>
    '${p.name} (${_ptToMm(p.portraitWidth)} × ${_ptToMm(p.portraitHeight)} mm)';

int _ptToMm(double pt) => (pt * 25.4 / 72).round();

/// The result of [recognizePaper]: either a named [preset] match or [isCustom].
class PaperMatch {
  /// A match against the standard [preset].
  const PaperMatch.preset(PaperPreset preset) : _preset = preset;

  /// No standard size matched — the page is a custom size.
  const PaperMatch.custom() : _preset = null;

  final PaperPreset? _preset;

  /// The matched standard size's name, or null when [isCustom].
  String? get name => _preset?.name;

  /// The matched size's display label (name + mm), or null when [isCustom].
  String? get label {
    final PaperPreset? p = _preset;
    return p == null ? null : paperPresetLabel(p);
  }

  /// Whether the page matches no standard size.
  bool get isCustom => _preset == null;
}

/// The half-point tolerance recognition allows on each side, so a page whose
/// dimensions were rounded to whole points (a panel shows `595`, an imported
/// template stores `595` instead of `595.28`) still names its standard size
/// (C1.4). Standard sizes differ by far more than this, so they stay distinct.
const double _kPaperTolerance = 0.5;

/// Names [page] by the standard size it matches in **either** orientation, or
/// reports [PaperMatch.isCustom] when none does. Pure and display-only — it
/// never alters [page] (FR-003). The page's two sides are sorted to {short,
/// long} before comparing, so portrait and landscape of the same size match.
PaperMatch recognizePaper(PageFormat page) {
  final double shortSide = page.width <= page.height ? page.width : page.height;
  final double longSide = page.width <= page.height ? page.height : page.width;
  for (final PaperPreset preset in kPaperPresets) {
    if ((shortSide - preset.portraitWidth).abs() <= _kPaperTolerance &&
        (longSide - preset.portraitHeight).abs() <= _kPaperTolerance) {
      return PaperMatch.preset(preset);
    }
  }
  return const PaperMatch.custom();
}

/// Builds a [PageFormat] at [preset]'s size — swapped to landscape when
/// [landscape] is true — carrying the supplied [margins] unchanged, so applying
/// a paper size never disturbs the current margins (FR-002). The controller
/// clamps the result before committing.
PageFormat applyPaper(
  PaperPreset preset, {
  required bool landscape,
  required JetEdgeInsets margins,
}) =>
    PageFormat(
      width: landscape ? preset.portraitHeight : preset.portraitWidth,
      height: landscape ? preset.portraitWidth : preset.portraitHeight,
      margins: margins,
    );
