/// The geometry of a multi-column label grid (spec 034) — an optional property
/// of the detail [Band] that serves as the label template.
///
/// Pure domain layer (no rendering/designer/Flutter UI). `columnWidth` is, in
/// effect, the detail band's render width; `columnSpacing` is the horizontal
/// gutter between columns and `rowSpacing` the vertical gap between label rows.
library;

/// An immutable label-grid spec: [columnCount] columns of [columnWidth] points,
/// separated by [columnSpacing] horizontally and [rowSpacing] vertically.
class ColumnLayout {
  /// Creates a column layout. All distances are in points.
  const ColumnLayout({
    required this.columnCount,
    required this.columnWidth,
    required this.columnSpacing,
    required this.rowSpacing,
  });

  /// Reads a [ColumnLayout] from its [toJson] map.
  factory ColumnLayout.fromJson(Map<String, Object?> json) => ColumnLayout(
        columnCount: (json['columnCount']! as num).toInt(),
        columnWidth: (json['columnWidth']! as num).toDouble(),
        columnSpacing: (json['columnSpacing']! as num).toDouble(),
        rowSpacing: (json['rowSpacing']! as num).toDouble(),
      );

  /// Number of columns across the page body.
  final int columnCount;

  /// Width of each column (cell), in points.
  final double columnWidth;

  /// Horizontal gutter between columns, in points.
  final double columnSpacing;

  /// Vertical gap between label rows, in points.
  final double rowSpacing;

  /// Returns a copy with the given fields replaced.
  ColumnLayout copyWith({
    int? columnCount,
    double? columnWidth,
    double? columnSpacing,
    double? rowSpacing,
  }) =>
      ColumnLayout(
        columnCount: columnCount ?? this.columnCount,
        columnWidth: columnWidth ?? this.columnWidth,
        columnSpacing: columnSpacing ?? this.columnSpacing,
        rowSpacing: rowSpacing ?? this.rowSpacing,
      );

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'columnCount': columnCount,
        'columnWidth': columnWidth,
        'columnSpacing': columnSpacing,
        'rowSpacing': rowSpacing,
      };

  @override
  bool operator ==(Object other) =>
      other is ColumnLayout &&
      other.columnCount == columnCount &&
      other.columnWidth == columnWidth &&
      other.columnSpacing == columnSpacing &&
      other.rowSpacing == rowSpacing;

  @override
  int get hashCode =>
      Object.hash(columnCount, columnWidth, columnSpacing, rowSpacing);

  @override
  String toString() => 'ColumnLayout($columnCount x ${columnWidth}pt, '
      'gap $columnSpacing/$rowSpacing)';
}
