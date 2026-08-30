/// The appearance and metrics of a crosstab (spec A). All distances are points.
library;

import '../styles/box_style.dart';
import '../styles/text_style.dart';
import '../value_equality.dart';

/// An immutable crosstab style. Cell appearance resolves in three layers:
/// a measure's own override, then this style, then the renderer's default.
class CrosstabStyle with ValueEquality {
  /// Creates a style; every field has a documented default.
  const CrosstabStyle({
    this.headerText,
    this.headerBox,
    this.cellText,
    this.cellBox,
    this.totalText,
    this.totalBox,
    this.rowLabelWidth = 110,
    this.rowLabelIndent = 12,
    this.measureColumnWidth = 64,
    this.rowHeight = 14,
    this.headerRowHeight = 14,
  });

  /// Text style for row and column header cells.
  final JetTextStyle? headerText;

  /// Box style behind header cells.
  final JetBoxStyle? headerBox;

  /// Text style for data cells.
  final JetTextStyle? cellText;

  /// Box style behind data cells.
  final JetBoxStyle? cellBox;

  /// Text style for subtotal and grand-total cells.
  final JetTextStyle? totalText;

  /// Box style behind total cells.
  final JetBoxStyle? totalBox;

  /// Width of the row-label column, repeated in every horizontal slice.
  final double rowLabelWidth;

  /// Horizontal indent applied per row-axis depth level.
  final double rowLabelIndent;

  /// Width of one measure column.
  final double measureColumnWidth;

  /// Height of a data or total row.
  final double rowHeight;

  /// Height of one column-header row.
  final double headerRowHeight;

  /// Returns a copy with the given fields replaced.
  ///
  /// The nullable style slots take thunks: omit to preserve, pass
  /// `() => value` to replace (`() => null` clears).
  CrosstabStyle copyWith({
    JetTextStyle? Function()? headerText,
    JetBoxStyle? Function()? headerBox,
    JetTextStyle? Function()? cellText,
    JetBoxStyle? Function()? cellBox,
    JetTextStyle? Function()? totalText,
    JetBoxStyle? Function()? totalBox,
    double? rowLabelWidth,
    double? rowLabelIndent,
    double? measureColumnWidth,
    double? rowHeight,
    double? headerRowHeight,
  }) =>
      CrosstabStyle(
        headerText: headerText == null ? this.headerText : headerText(),
        headerBox: headerBox == null ? this.headerBox : headerBox(),
        cellText: cellText == null ? this.cellText : cellText(),
        cellBox: cellBox == null ? this.cellBox : cellBox(),
        totalText: totalText == null ? this.totalText : totalText(),
        totalBox: totalBox == null ? this.totalBox : totalBox(),
        rowLabelWidth: rowLabelWidth ?? this.rowLabelWidth,
        rowLabelIndent: rowLabelIndent ?? this.rowLabelIndent,
        measureColumnWidth: measureColumnWidth ?? this.measureColumnWidth,
        rowHeight: rowHeight ?? this.rowHeight,
        headerRowHeight: headerRowHeight ?? this.headerRowHeight,
      );

  @override
  List<Object?> get props => <Object?>[
        headerText,
        headerBox,
        cellText,
        cellBox,
        totalText,
        totalBox,
        rowLabelWidth,
        rowLabelIndent,
        measureColumnWidth,
        rowHeight,
        headerRowHeight,
      ];

  @override
  String toString() =>
      'CrosstabStyle(label ${rowLabelWidth}pt, col ${measureColumnWidth}pt, '
      'row ${rowHeight}pt)';
}
