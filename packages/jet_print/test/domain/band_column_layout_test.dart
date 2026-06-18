import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/report_band.dart';

void main() {
  const ColumnLayout grid = ColumnLayout(
      columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);

  test('columnLayout defaults to null and is value-equal when absent', () {
    const Band a = Band(id: 'd', type: BandType.detail, height: 80);
    const Band b = Band(id: 'd', type: BandType.detail, height: 80);
    expect(a.columnLayout, isNull);
    expect(a, b);
  });

  test('a band carrying columnLayout differs from one without', () {
    const Band withGrid =
        Band(id: 'd', type: BandType.detail, height: 80, columnLayout: grid);
    const Band withoutGrid = Band(id: 'd', type: BandType.detail, height: 80);
    expect(withGrid, isNot(withoutGrid));
    expect(withGrid.columnLayout, grid);
  });

  test('copyWith preserves columnLayout when not overridden', () {
    const Band withGrid =
        Band(id: 'd', type: BandType.detail, height: 80, columnLayout: grid);
    expect(withGrid.copyWith(height: 90).columnLayout, grid);
    expect(
        withGrid
            .copyWith(columnLayout: grid.copyWith(columnCount: 2))
            .columnLayout!
            .columnCount,
        2);
  });
}
