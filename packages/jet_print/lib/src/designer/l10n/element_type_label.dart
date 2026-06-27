/// Maps a [ReportElement]'s `typeKey` to its localized display name, used by the
/// canvas accessibility labels and the inspector. Mirrors [bandTypeLabel].
library;

import '../../domain/report_element.dart';
import 'jet_print_localizations.dart';

/// The localized type name for [element] (e.g. "Text", "Bild", "Şekil"); falls
/// back to a generic "Element" for unknown/extension types.
String elementTypeLabel(ReportElement element, JetPrintLocalizations l10n) {
  switch (element.typeKey) {
    case 'text':
      return l10n.elementTypeText;
    case 'shape':
      return l10n.elementTypeShape;
    case 'image':
      return l10n.elementTypeImage;
    case 'barcode':
      return l10n.elementTypeBarcode;
    case 'chart':
      return l10n.elementTypeChart;
    default:
      return l10n.elementTypeGeneric;
  }
}
