/// The physical page a report is laid out onto.
library;

import 'geometry.dart';

/// An immutable page description: a [width] x [height] sheet (in logical points)
/// with [margins]. Defaults are provided for common formats.
class PageFormat {
  /// Creates a page format.
  const PageFormat({
    required this.width,
    required this.height,
    required this.margins,
  });

  /// Reads a [PageFormat] from its [toJson] map.
  factory PageFormat.fromJson(Map<String, Object?> json) => PageFormat(
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
        margins: JetEdgeInsets.fromJson(
            (json['margins']! as Map).cast<String, Object?>()),
      );

  /// ISO A4 portrait (595.28 x 841.89 pt) with ~1 cm margins.
  static const PageFormat a4Portrait = PageFormat(
    width: 595.28,
    height: 841.89,
    margins: JetEdgeInsets.all(28.35),
  );

  /// Page width, in points.
  final double width;

  /// Page height, in points.
  final double height;

  /// Page margins, in points.
  final JetEdgeInsets margins;

  /// Returns a copy with the given fields replaced and the rest preserved.
  ///
  /// Additive only — no new field, and serialization is unaffected. The designer
  /// composes a page edit by `copyWith`-ing the live page (swap width/height for
  /// orientation, set [margins], change one dimension) and handing the result to
  /// `JetReportDesignerController.setPageFormat`, which clamps and commits it.
  PageFormat copyWith(
          {double? width, double? height, JetEdgeInsets? margins}) =>
      PageFormat(
        width: width ?? this.width,
        height: height ?? this.height,
        margins: margins ?? this.margins,
      );

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
        'margins': margins.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is PageFormat &&
      other.width == width &&
      other.height == height &&
      other.margins == margins;

  @override
  int get hashCode => Object.hash(width, height, margins);

  @override
  String toString() => 'PageFormat(${width}x$height, $margins)';
}
