/// The blank design a no-argument designer/controller starts from.
library;

import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart' show BandType;
import '../../domain/report_definition.dart';

/// Returns a fresh, empty [ReportDefinition] on A4 portrait with a conventional
/// structure: a page header and page footer in the record-blind [PageFurniture]
/// and a single detail band in the master [DetailScope].
///
/// This is what `JetReportDesignerController()` and `const JetReportDesigner()`
/// seed from so the widget is drop-in with no arguments (contracts §2). The name
/// is intentionally empty so the unified toolbar shows the *localized* "untitled"
/// placeholder for a fresh report (FR-010); the host renames via the model. The
/// band ids are stable, conventional slugs so a fresh design is addressable
/// immediately (FR-002).
ReportDefinition defaultBlankDefinition() => const ReportDefinition(
      name: '',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader:
            Band(id: 'pageHeader', type: BandType.pageHeader, height: 64),
        pageFooter:
            Band(id: 'pageFooter', type: BandType.pageFooter, height: 48),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 200)),
          ],
        ),
      ),
    );
