/// The blank design a no-argument designer/controller starts from.
library;

import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_template.dart';

/// Returns a fresh, empty [ReportTemplate] on A4 portrait with a conventional
/// three-band structure (page header / detail / page footer).
///
/// This is what `JetReportDesignerController()` and `const JetReportDesigner()`
/// seed from so the widget is drop-in with no arguments (contracts §2). The name
/// is intentionally empty so the unified toolbar shows the *localized* "untitled"
/// placeholder for a fresh report (FR-010); the host renames via the model.
ReportTemplate defaultBlankTemplate() => const ReportTemplate(
      name: '',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(type: BandType.pageHeader, height: 64),
        ReportBand(type: BandType.detail, height: 200),
        ReportBand(type: BandType.pageFooter, height: 48),
      ],
    );
