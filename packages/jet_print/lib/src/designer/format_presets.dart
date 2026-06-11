/// Format quick-picks for the label Format field (013) — a small, fixed starter
/// set. Only the resulting [FormatPreset.pattern] string ever reaches the model
/// (`TextElement.format`); the preset identity is not persisted.
library;

import 'l10n/jet_print_localizations.dart';

/// A named format preset: a localized [label] and the ICU [pattern] it fills
/// into the Format field. The empty pattern (None) clears the format.
class FormatPreset {
  /// Creates a preset.
  const FormatPreset(this.label, this.pattern);

  /// The localized, user-facing name.
  final String label;

  /// The ICU number/date pattern (empty = clear).
  final String pattern;
}

/// The seven presets (013), in display order, localized via [l10n].
List<FormatPreset> formatPresets(JetPrintLocalizations l10n) => <FormatPreset>[
      FormatPreset(l10n.formatPresetNone, ''),
      FormatPreset(l10n.formatPresetInteger, '#,##0'),
      FormatPreset(l10n.formatPresetDecimal, '#,##0.00'),
      FormatPreset(l10n.formatPresetCurrency, '¤#,##0.00'),
      FormatPreset(l10n.formatPresetPercent, '#,##0%'),
      FormatPreset(l10n.formatPresetDate, 'yyyy-MM-dd'),
      FormatPreset(l10n.formatPresetDateTime, 'yyyy-MM-dd HH:mm'),
    ];
