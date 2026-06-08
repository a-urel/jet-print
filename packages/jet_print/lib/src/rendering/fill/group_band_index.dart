/// Validates and indexes a template's group header/footer bands (spec 007c
/// §4/§6). Built once per fill.
///
/// **Fail-fast:** the constructor throws [ReportFormatException] on duplicate
/// [ReportGroup] names — name-keyed routing would replay the same band bucket for
/// each colliding group, over-emitting. A successfully built index therefore has
/// unique group names and unambiguous lookups.
///
/// **Recoverable:** a `groupHeader`/`groupFooter` band whose [ReportBand.group]
/// is null or names a group not declared in the template records an error
/// [Diagnostic] and is excluded; the rest of the report still renders.
library;

import '../../domain/report_band.dart';
import '../../domain/report_group.dart';
import '../../domain/report_template.dart';
import '../../domain/serialization/report_format_exception.dart';
import 'report_diagnostics.dart';

/// A lookup from group name to its (validated, authored-order) header/footer
/// bands.
class GroupBandIndex {
  /// Builds the index from [template], recording recoverable issues into
  /// [diagnostics] and throwing [ReportFormatException] on duplicate group names.
  GroupBandIndex(ReportTemplate template, ReportDiagnostics diagnostics) {
    final Set<String> declared = <String>{};
    final Set<String> duplicates = <String>{};
    for (final ReportGroup group in template.groups) {
      if (!declared.add(group.name)) {
        duplicates.add(group.name);
      }
    }
    if (duplicates.isNotEmpty) {
      final List<String> names = duplicates.toList()..sort();
      throw ReportFormatException('Duplicate group name(s): ${names.join(', ')}');
    }

    for (final ReportBand band in template.bands) {
      if (band.type != BandType.groupHeader &&
          band.type != BandType.groupFooter) {
        continue;
      }
      final String? name = band.group;
      if (name == null) {
        diagnostics.error('${band.type.name} band must declare a group');
        continue;
      }
      if (!declared.contains(name)) {
        diagnostics
            .error('${band.type.name} band references unknown group "$name"');
        continue;
      }
      final Map<String, List<ReportBand>> target =
          band.type == BandType.groupHeader ? _headers : _footers;
      (target[name] ??= <ReportBand>[]).add(band);
    }

    // Freeze the buckets so the index is immutable after construction (matching
    // the codebase's frozen-snapshot convention: FilledReport, calc.values,
    // ReportDiagnostics.entries).
    _headers.updateAll(
        (String key, List<ReportBand> v) => List<ReportBand>.unmodifiable(v));
    _footers.updateAll(
        (String key, List<ReportBand> v) => List<ReportBand>.unmodifiable(v));
  }

  final Map<String, List<ReportBand>> _headers = <String, List<ReportBand>>{};
  final Map<String, List<ReportBand>> _footers = <String, List<ReportBand>>{};

  /// The `groupHeader` bands for [groupName] in authored order (unmodifiable;
  /// empty if none).
  List<ReportBand> headersFor(String groupName) =>
      _headers[groupName] ?? const <ReportBand>[];

  /// The `groupFooter` bands for [groupName] in authored order (unmodifiable;
  /// empty if none).
  List<ReportBand> footersFor(String groupName) =>
      _footers[groupName] ?? const <ReportBand>[];
}
