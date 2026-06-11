/// Format quick-picks for the label Format field (013) — a small, fixed starter
/// set. Only the resulting [FormatPreset.pattern] string ever reaches the model
/// (`TextElement.format`); the preset identity is not persisted.
library;

import '../data/field_def.dart';
import 'l10n/jet_print_localizations.dart';

/// What kind of value a preset's pattern is meant for, so the Format picker can
/// disable presets that cannot apply to a bound field's type (numeric patterns
/// on a date, etc.). [none] (the clear) always applies.
enum FormatPresetKind { none, numeric, date }

/// A named format preset: a localized [label] and the ICU [pattern] it fills
/// into the Format field. The empty pattern (None) clears the format.
class FormatPreset {
  /// Creates a preset of the given [kind].
  const FormatPreset(this.label, this.pattern, this.kind);

  /// The localized, user-facing name.
  final String label;

  /// The ICU number/date pattern (empty = clear).
  final String pattern;

  /// The value kind this pattern targets (gates [enabledFor]).
  final FormatPresetKind kind;

  /// Whether this preset can apply to a bound value of [type]. A null type
  /// (literal text, an advanced template, or no schema) or an [JetFieldType.unknown]
  /// field leaves every preset enabled — the type is not pinned down, so the
  /// designer is not second-guessed. Otherwise numeric presets apply only to
  /// integer/double fields and date presets only to dateTime fields; [None] is
  /// always available to clear the format.
  bool enabledFor(JetFieldType? type) {
    if (type == null || type == JetFieldType.unknown) return true;
    return switch (kind) {
      FormatPresetKind.none => true,
      FormatPresetKind.numeric =>
        type == JetFieldType.integer || type == JetFieldType.double,
      FormatPresetKind.date => type == JetFieldType.dateTime,
    };
  }
}

/// The seven presets (013), in display order, localized via [l10n].
List<FormatPreset> formatPresets(JetPrintLocalizations l10n) => <FormatPreset>[
      FormatPreset(l10n.formatPresetNone, '', FormatPresetKind.none),
      FormatPreset(l10n.formatPresetInteger, '#,##0', FormatPresetKind.numeric),
      FormatPreset(
          l10n.formatPresetDecimal, '#,##0.00', FormatPresetKind.numeric),
      FormatPreset(
          l10n.formatPresetCurrency, '¤#,##0.00', FormatPresetKind.numeric),
      FormatPreset(
          l10n.formatPresetPercent, '#,##0%', FormatPresetKind.numeric),
      FormatPreset(l10n.formatPresetDate, 'yyyy-MM-dd', FormatPresetKind.date),
      FormatPreset(
          l10n.formatPresetDateTime, 'yyyy-MM-dd HH:mm', FormatPresetKind.date),
    ];
