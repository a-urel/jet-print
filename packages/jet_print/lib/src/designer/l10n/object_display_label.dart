/// Resolves the label shown for a report object in the Properties header and
/// the Outline tree. A single source of truth so both surfaces agree (and a
/// rename is reflected identically in each).
library;

import '../../domain/band.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/report_element.dart';
import 'band_type_label.dart';
import 'element_type_label.dart';
import 'jet_print_localizations.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// The label for [element]: its display [ReportElement.name] when set; else a
/// [TextElement]'s literal text when non-blank; else the localized type label.
String elementDisplayLabel(
    ReportElement element, JetPrintLocalizations l10n) {
  if (!_blank(element.name)) return element.name!.trim();
  if (element is TextElement && !_blank(element.text)) return element.text;
  return elementTypeLabel(element, l10n);
}

/// The label for [band]: its display [Band.name] when set; else the localized
/// band-type label.
String bandDisplayLabel(Band band, JetPrintLocalizations l10n) {
  if (!_blank(band.name)) return band.name!.trim();
  return bandTypeLabel(band.type, l10n);
}
