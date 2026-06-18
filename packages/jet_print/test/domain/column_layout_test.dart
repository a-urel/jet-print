import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/column_layout.dart';

void main() {
  const ColumnLayout a = ColumnLayout(
      columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);

  test('value equality and hashCode', () {
    const ColumnLayout b = ColumnLayout(
        columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
    const ColumnLayout c = ColumnLayout(
        columnCount: 2, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('copyWith replaces only the given field', () {
    expect(
        a.copyWith(columnCount: 4),
        const ColumnLayout(
            columnCount: 4,
            columnWidth: 180,
            columnSpacing: 12,
            rowSpacing: 8));
  });

  test('toJson / fromJson round-trips value-equal', () {
    final Map<String, Object?> json = a.toJson();
    expect(json, <String, Object?>{
      'columnCount': 3,
      'columnWidth': 180.0,
      'columnSpacing': 12.0,
      'rowSpacing': 8.0,
    });
    expect(ColumnLayout.fromJson(json), a);
  });
}
