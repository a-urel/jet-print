/// The localized caption for a band type, shared by the canvas band badges and
/// the Outline panel so both name a band identically.
library;

import '../../domain/report_band.dart';
import 'jet_print_localizations.dart';

/// The localized display caption for [type] (e.g. `BandType.pageHeader` →
/// "Page Header" / "Seitenkopf" / "Sayfa Başlığı").
String bandTypeLabel(BandType type, JetPrintLocalizations l10n) {
  switch (type) {
    case BandType.title:
      return l10n.bandTypeTitle;
    case BandType.pageHeader:
      return l10n.bandTypePageHeader;
    case BandType.columnHeader:
      return l10n.bandTypeColumnHeader;
    case BandType.groupHeader:
      return l10n.bandTypeGroupHeader;
    case BandType.detail:
      return l10n.bandTypeDetail;
    case BandType.groupFooter:
      return l10n.bandTypeGroupFooter;
    case BandType.columnFooter:
      return l10n.bandTypeColumnFooter;
    case BandType.pageFooter:
      return l10n.bandTypePageFooter;
    case BandType.summary:
      return l10n.bandTypeSummary;
    case BandType.background:
      return l10n.bandTypeBackground;
    case BandType.noData:
      return l10n.bandTypeNoData;
  }
}
