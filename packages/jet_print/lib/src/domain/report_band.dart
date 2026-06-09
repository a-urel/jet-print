/// Horizontal bands — the vertical structure of a banded report.
library;

import 'report_element.dart';

/// The role a band plays in the report's vertical flow. The renderer (spec 008)
/// decides repetition/placement per type; here it is pure structure.
enum BandType {
  /// Printed once at the very start of the report.
  title,

  /// Repeated at the top of every page.
  pageHeader,

  /// Repeated above the detail section on each page/column.
  columnHeader,

  /// Printed when a group's key changes (before its details).
  groupHeader,

  /// Repeated once per data row.
  detail,

  /// Printed when a group ends (after its details).
  groupFooter,

  /// Repeated below the detail section on each page/column.
  columnFooter,

  /// Repeated at the bottom of every page.
  pageFooter,

  /// Printed once at the very end of the report.
  summary,

  /// Drawn behind every page (watermarks, frames).
  background,

  /// Printed instead of details when the data set is empty.
  noData,
}

/// An ordered, fixed-height band holding absolutely-positioned [elements], and
/// optionally — for master/detail (009) — bound to a nested-collection field via
/// [collectionField] and nesting deeper data bands in [children].
class ReportBand {
  /// Creates a band of [type] and [height] points containing [elements].
  const ReportBand({
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
    this.group,
    this.collectionField,
    this.children = const <ReportBand>[],
  });

  /// The band's role in the report flow.
  final BandType type;

  /// The band's designed height, in points (may grow at layout time later).
  final double height;

  /// Elements placed within the band, at absolute bounds.
  final List<ReportElement> elements;

  /// The name of the [ReportGroup] this band belongs to (007c). Meaningful only
  /// for [BandType.groupHeader]/[BandType.groupFooter]; null (and ignored) for
  /// every other band type.
  final String? group;

  /// The nested-collection field (in the attached schema) this band iterates,
  /// or null when the band is in the master scope (009). A non-null value makes
  /// the band a **detail** band that repeats over the collection's child rows,
  /// and establishes the child scope its [elements] and [children] resolve
  /// against.
  final String? collectionField;

  /// Data bands nested **within** this band's child scope (009), enabling
  /// arbitrarily deep master/detail (e.g. invoice → lines → sub-lines). Empty
  /// for a leaf band.
  final List<ReportBand> children;

  /// Returns a copy with the given fields replaced. The most common edit —
  /// replacing the [elements] list when a single band is touched — preserves
  /// every other band referentially (FR-025 non-destructiveness).
  ReportBand copyWith({
    BandType? type,
    double? height,
    List<ReportElement>? elements,
    String? group,
    String? collectionField,
    List<ReportBand>? children,
  }) =>
      ReportBand(
        type: type ?? this.type,
        height: height ?? this.height,
        elements: elements ?? this.elements,
        group: group ?? this.group,
        collectionField: collectionField ?? this.collectionField,
        children: children ?? this.children,
      );
}
