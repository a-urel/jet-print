/// A reified band: an addressable, typed, fixed-height container of elements.
///
/// Part of the reified report model (spec 024). Unlike the legacy
/// [ReportBand], a [Band] is a pure leaf: it carries a stable [id] and its
/// structural role is given by *where it sits* in the tree (a furniture slot, a
/// group header/footer, or a per-row [BandNode]). Its [type] is retained for
/// labels, glyphs, identity, and faithful migration, and is validated
/// consistent with that slot — but position, not [type], is authoritative.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'column_layout.dart';
import 'report_band.dart' show BandType;
import 'report_element.dart';

/// An ordered, fixed-height band holding absolutely-positioned [elements],
/// addressable by a stable [id] (enabling add/remove/reorder/retype and
/// id-based selection — FR-002).
class Band {
  /// Creates a band identified by [id], of [type] and [height] points,
  /// containing [elements].
  const Band({
    required this.id,
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
    this.columnLayout,
    this.name,
  });

  /// Stable identity (selection + lifecycle are no longer index-based).
  final String id;

  /// The band's role marker (retained — Q1). Authoritative role comes from the
  /// band's position in the tree; [type] is validated consistent with it.
  final BandType type;

  /// The band's designed height, in points.
  final double height;

  /// Elements placed within the band, at absolute bounds.
  final List<ReportElement> elements;

  /// When non-null on the lone detail band of a pure single-detail body, lays
  /// the band out as a multi-column label grid (spec 034). Null elsewhere.
  final ColumnLayout? columnLayout;

  /// Optional human-facing display name; when null/blank the Outline and
  /// Properties show the localized [bandTypeLabel]. Unconstrained.
  final String? name;

  /// Returns a copy with the given fields replaced.
  Band copyWith({
    String? id,
    BandType? type,
    double? height,
    List<ReportElement>? elements,
    ColumnLayout? columnLayout,
    String? name,
  }) =>
      Band(
        id: id ?? this.id,
        type: type ?? this.type,
        height: height ?? this.height,
        elements: elements ?? this.elements,
        columnLayout: columnLayout ?? this.columnLayout,
        name: name ?? this.name,
      );

  @override
  bool operator ==(Object other) =>
      other is Band &&
      other.id == id &&
      other.type == type &&
      other.height == height &&
      listEquals(other.elements, elements) &&
      other.columnLayout == columnLayout &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(id, type, height, Object.hashAll(elements), columnLayout, name);

  @override
  String toString() => 'Band($id, ${type.name}, ${height}pt, '
      '${elements.length} element(s))';
}
