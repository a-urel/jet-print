/// The physical page a report is laid out onto.
library;

import 'geometry.dart';
import 'value_equality.dart';

/// An immutable page description: a [width] x [height] sheet (in logical points)
/// with [margins]. Defaults are provided for common formats.
///
/// A [continuous] page is roll paper, as a receipt or kitchen-ticket printer
/// feeds it: each rendered page grows to fit its content, and [height] is only
/// the shortest a page may be.
class PageFormat with ValueEquality {
  /// Creates a page format.
  const PageFormat({
    required this.width,
    required this.height,
    required this.margins,
    this.continuous = false,
  });

  /// Reads a [PageFormat] from its [toJson] map.
  factory PageFormat.fromJson(Map<String, Object?> json) => PageFormat(
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
        margins: JetEdgeInsets.fromJson(
            (json['margins']! as Map).cast<String, Object?>()),
        continuous: json['continuous'] as bool? ?? false,
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
  ///
  /// On a [continuous] page this is the minimum height: a rendered page is
  /// never shorter, and grows past it to fit its content.
  final double height;

  /// Page margins, in points.
  final JetEdgeInsets margins;

  /// Whether this is roll paper rather than a sheet.
  ///
  /// When `true`, rendering never breaks a page because it is full: each
  /// rendered page is as tall as its content (header, body, footer and
  /// margins), and never shorter than [height]. A page still ends where the
  /// report asks for one — a group that starts a new page — so one report can
  /// produce several tickets, each cut to its own length. The page footer
  /// follows the content rather than sitting at a fixed bottom, and a label
  /// grid lays every label on a single page.
  ///
  /// Serialized only when `true`, so a sheet page's JSON is unchanged. A build
  /// older than this field reads such a page as a sheet [height] tall and
  /// drops the key when it saves.
  final bool continuous;

  /// Returns a copy with the given fields replaced and the rest preserved.
  ///
  /// The designer composes a page edit by `copyWith`-ing the live page (swap
  /// width/height for orientation, set [margins], change one dimension, switch
  /// [continuous]) and handing the result to
  /// `JetReportDesignerController.setPageFormat`, which clamps and commits it.
  PageFormat copyWith({
    double? width,
    double? height,
    JetEdgeInsets? margins,
    bool? continuous,
  }) =>
      PageFormat(
        width: width ?? this.width,
        height: height ?? this.height,
        margins: margins ?? this.margins,
        continuous: continuous ?? this.continuous,
      );

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
        'margins': margins.toJson(),
        if (continuous) 'continuous': true,
      };

  @override
  List<Object?> get props => <Object?>[width, height, margins, continuous];

  @override
  String toString() =>
      'PageFormat(${width}x$height, $margins${continuous ? ', continuous' : ''})';
}
