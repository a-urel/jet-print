// Confirms the label sample is authored as a single label cell on a detail band
// carrying a native ColumnLayout (spec 034) over a flat address schema, that the
// body is a pure single-detail body so the grid activates, and that it is
// pristine under the library validator — all through
// `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/label_sample.dart';

void main() {
  group('label sample', () {
    test('is one per-row detail band on a furniture-free root scope', () {
      final ReportDefinition def = labelSampleDefinition();

      // Labels carry no page chrome.
      expect(def.furniture.pageHeader, isNull);
      expect(def.furniture.pageFooter, isNull);

      // The master scope iterates the flat address rows (a root scope carries
      // no collectionField), with exactly one per-row detail band.
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);
      expect(root.children, hasLength(1));
      expect(root.children.single, isA<BandNode>());
      final Band band = (root.children.single as BandNode).band;
      expect(band.type, BandType.detail);
    });

    test('the detail band carries a 3-column native ColumnLayout', () {
      final ReportDefinition def = labelSampleDefinition();

      // The body must be a pure single-detail body so the engine activates the
      // grid; its sole detail band is the one carrying the layout.
      expect(def.isPureSingleDetailBody, isTrue);
      final Band? sole = def.soleDetailBand;
      expect(sole, isNotNull);

      final ColumnLayout? layout = sole!.columnLayout;
      expect(layout, isNotNull);
      expect(layout!.columnCount, labelColumns);
      expect(layout.columnCount, 3);
      expect(layout.columnWidth, 170);
      expect(layout.columnSpacing, 9);
      expect(layout.rowSpacing, 0);

      // The grid fits the A4 portrait body (≈538 pt): 3·170 + 2·9 = 528.
      final double grid = layout.columnCount * layout.columnWidth +
          (layout.columnCount - 1) * layout.columnSpacing;
      expect(grid, lessThan(538));
    });

    test('the band authors exactly one address cell, bound to flat fields', () {
      final Band band =
          (labelSampleDefinition().body.root.children.single as BandNode).band;

      // One cell only (the grid repeats it) — a border + four address lines.
      expect(band.elements.whereType<ShapeElement>(), hasLength(1));
      final List<TextElement> texts =
          band.elements.whereType<TextElement>().toList();
      expect(texts, hasLength(4));

      // Each line binds its flat field name (no per-cell prefix), and all sit
      // within the cell width (columnWidth 170) so nothing is clipped.
      for (final String field in <String>['name', 'street', 'city', 'country']) {
        final TextElement t =
            texts.firstWhere((TextElement e) => e.id == field);
        expect(t.expression, '\$F{$field}');
        expect(t.bounds.x + t.bounds.width, lessThanOrEqualTo(170.0));
      }
    });

    test('the schema declares the four flat address fields', () {
      expect(labelSchema.fields, hasLength(4));
      expect(
        labelSchema.fields.map((FieldDef f) => f.name),
        containsAll(<String>['name', 'street', 'city', 'country']),
      );
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(labelSampleDefinition()), isEmpty);
    });
  });
}
