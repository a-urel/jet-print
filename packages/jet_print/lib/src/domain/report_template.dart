/// The root of a report definition.
library;

import 'page_format.dart';
import 'report_band.dart';
import 'report_group.dart';
import 'report_parameter.dart';
import 'report_variable.dart';

/// An immutable report definition: a named [page] layout with ordered [bands],
/// plus declared [parameters], [variables], and [groups].
/// This is the artifact that serializes to versioned JSON (Constitution V).
class ReportTemplate {
  /// Creates a report template.
  const ReportTemplate({
    required this.name,
    required this.page,
    this.bands = const <ReportBand>[],
    this.parameters = const <ReportParameter>[],
    this.variables = const <ReportVariable>[],
    this.groups = const <ReportGroup>[],
  });

  /// Human-readable template name.
  final String name;

  /// The page the report is laid out onto.
  final PageFormat page;

  /// The report's bands, in vertical/role order.
  final List<ReportBand> bands;

  /// Declared parameters (external inputs resolved by `$P{}`).
  final List<ReportParameter> parameters;

  /// Declared variables (accumulated/derived values resolved by `$V{}`).
  final List<ReportVariable> variables;

  /// Declared groups, outermost first (reset boundaries for variables).
  final List<ReportGroup> groups;
}
