/// The root of a report definition.
library;

import 'page_format.dart';
import 'report_band.dart';

/// An immutable report definition: a named [page] layout with ordered [bands].
/// This is the artifact that serializes to versioned JSON (Constitution V).
class ReportTemplate {
  /// Creates a report template.
  const ReportTemplate({
    required this.name,
    required this.page,
    this.bands = const <ReportBand>[],
  });

  /// Human-readable template name.
  final String name;

  /// The page the report is laid out onto.
  final PageFormat page;

  /// The report's bands, in vertical/role order.
  final List<ReportBand> bands;
}
