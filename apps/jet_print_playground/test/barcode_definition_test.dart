// Confirms the barcode sample is authored as a single product-label cell on a
// detail band carrying a native ColumnLayout (spec 034) over a flat product
// schema, that the cell carries a real EAN-13 barcode bound to the product
// number (spec 036), that the body is a pure single-detail body so the grid
// activates, and that it is pristine under the library validator — all through
// `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/barcode_sample.dart';

void main() {
  group('barcode sample', () {
    test('is one per-row detail band on a furniture-free root scope', () {
      final ReportDefinition def = barcodeSampleDefinition();

      // Labels carry no page chrome.
      expect(def.furniture.pageHeader, isNull);
      expect(def.furniture.pageFooter, isNull);

      // The master scope iterates the flat product rows (a root scope carries
      // no collectionField), with exactly one per-row detail band.
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);
      expect(root.children, hasLength(1));
      expect(root.children.single, isA<BandNode>());
      final Band band = (root.children.single as BandNode).band;
      expect(band.type, BandType.detail);
    });

    test('the detail band carries a 2-column native ColumnLayout', () {
      final ReportDefinition def = barcodeSampleDefinition();

      // The body must be a pure single-detail body so the engine activates the
      // grid; its sole detail band is the one carrying the layout.
      expect(def.isPureSingleDetailBody, isTrue);
      final Band? sole = def.soleDetailBand;
      expect(sole, isNotNull);

      final ColumnLayout? layout = sole!.columnLayout;
      expect(layout, isNotNull);
      expect(layout!.columnCount, barcodeColumns);
      expect(layout.columnCount, 2);
      expect(layout.columnWidth, 260);
      expect(layout.columnSpacing, 18);
      expect(layout.rowSpacing, 0);

      // The grid fits the A4 portrait body (≈538 pt): 2·260 + 1·18 = 538.
      final double grid = layout.columnCount * layout.columnWidth +
          (layout.columnCount - 1) * layout.columnSpacing;
      expect(grid, lessThanOrEqualTo(538.0));
    });

    test(
        'the band authors one cell: a border, a product name, a price, and a '
        'barcode', () {
      final Band band =
          (barcodeSampleDefinition().body.root.children.single as BandNode)
              .band;

      // One cell only (the grid repeats it): a border tile…
      expect(band.elements.whereType<ShapeElement>(), hasLength(1));

      // …a product-name line bound to the flat `product` field and a price line
      // bound to the flat `price` field…
      final List<TextElement> texts =
          band.elements.whereType<TextElement>().toList();
      expect(texts, hasLength(2));
      expect(
        texts.map((TextElement t) => t.expression),
        containsAll(<String>['\$F{product}', '\$F{price}']),
      );

      // …and exactly one EAN-13 barcode, bound to the `sku` product number, that
      // sits within the cell width (columnWidth 260) so nothing is clipped.
      final List<BarcodeElement> barcodes =
          band.elements.whereType<BarcodeElement>().toList();
      expect(barcodes, hasLength(1));
      final BarcodeElement barcode = barcodes.single;
      // Symbology stays at the default auto; the engine infers EAN-13 from the
      // 13-digit numeric value at fill time.
      expect(barcode.symbology, BarcodeSymbology.auto);
      expect(barcode.dataField, 'sku');
      expect(barcode.bounds.x + barcode.bounds.width, lessThanOrEqualTo(260.0));
    });

    test('the schema declares the flat product fields', () {
      expect(barcodeSchema.fields, hasLength(3));
      expect(
        barcodeSchema.fields.map((FieldDef f) => f.name),
        containsAll(<String>['product', 'price', 'sku']),
      );
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(barcodeSampleDefinition()), isEmpty);
    });
  });
}
