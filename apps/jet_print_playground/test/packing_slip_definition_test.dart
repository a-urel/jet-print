// Confirms the packing-slip sample (Shipment ▸ Box ▸ Item) is authored as a
// genuinely nested tree in the reified band model (spec 024): boxes nested
// under a shipment GroupLevel, items nested under each box, with per-box and
// grand totals expressed as inline aggregates — pristine under the validator.
// All through `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/packing_slip_sample.dart';

void main() {
  group('packing-slip sample', () {
    test('schema is Shipment ▸ boxes ▸ items with the two stored measures', () {
      final FieldDef boxes = shipmentSchema.fields
          .firstWhere((FieldDef f) => f.name == 'boxes');
      expect(boxes.type, JetFieldType.collection);
      final FieldDef items =
          boxes.fields.firstWhere((FieldDef f) => f.name == 'items');
      expect(items.type, JetFieldType.collection);
      final FieldDef qty =
          items.fields.firstWhere((FieldDef f) => f.name == 'qtyShipped');
      final FieldDef weight =
          items.fields.firstWhere((FieldDef f) => f.name == 'lineWeight');
      expect(qty.type, JetFieldType.integer);
      expect(weight.type, JetFieldType.double);
    });

    test('is authored Shipment ▸ Box ▸ Item, two nested scopes deep', () {
      final ReportDefinition def = packingSlipDefinition();

      // Page chrome lives in record-blind furniture; signature in the summary.
      expect(def.furniture.pageHeader?.type, BandType.pageHeader);
      expect(def.furniture.pageFooter?.type, BandType.pageFooter);
      expect(def.body.summary?.type, BandType.summary);

      // The master scope iterates the shipment (root carries no collectionField).
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);

      // The shipment is a first-class group owning header + grand-total footer.
      expect(root.groups, hasLength(1));
      final GroupLevel shipment = root.groups.single;
      expect(shipment.key, r'$F{shipmentNo}');
      expect(shipment.header?.type, BandType.groupHeader);
      expect(shipment.footer?.type, BandType.groupFooter);

      // List #1: boxes nested under the shipment.
      expect(root.children, hasLength(1));
      final DetailScope boxes = (root.children.single as NestedScope).scope;
      expect(boxes.collectionField, 'boxes');
      expect((boxes.children.first as BandNode).band.type, BandType.detail);

      // List #2: items nested under each box — a list within a list — with a
      // box-subtotal footer.
      final DetailScope items =
          boxes.children.whereType<NestedScope>().single.scope;
      expect(items.collectionField, 'items');
      expect((items.children.single as BandNode).band.type, BandType.detail);
      expect(items.footer?.type, BandType.groupFooter);
    });

    test('totals are authored inline (no stored totals, no ScopeTotal)', () {
      final ReportDefinition def = packingSlipDefinition();
      expect(def.variables, isEmpty);

      final DetailScope root = def.body.root;
      final DetailScope boxes = (root.children.single as NestedScope).scope;
      final DetailScope items =
          boxes.children.whereType<NestedScope>().single.scope;
      expect(boxes.totals, isEmpty);
      expect(items.totals, isEmpty);

      // Box-subtotal footer folds the box's own items (spec 029 same-scope).
      final TextElement boxUnits = items.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'boxUnits') as TextElement;
      expect(boxUnits.expression, r'SUM($F{qtyShipped})');

      // Grand-total footer descends [boxes, items] for units/weight and
      // [boxes] for the box count (spec 033 inline fold).
      final GroupLevel shipment = root.groups.single;
      final TextElement totalBoxes = shipment.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'totalBoxes') as TextElement;
      final TextElement totalUnits = shipment.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'totalUnits') as TextElement;
      final TextElement totalWeight = shipment.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'totalWeight') as TextElement;
      expect(totalBoxes.expression, r'COUNT($F{boxNo})');
      expect(totalUnits.expression, r'SUM($F{qtyShipped})');
      expect(totalWeight.expression, r'SUM($F{lineWeight})');
    });

    test('the tracking code is a QR barcode bound to trackingNo', () {
      final ReportDefinition def = packingSlipDefinition();
      final GroupLevel shipment = def.body.root.groups.single;
      final BarcodeElement qr = shipment.header!.elements
          .firstWhere((ReportElement e) => e.id == 'trackingQr')
          as BarcodeElement;
      expect(qr.symbology, BarcodeSymbology.qrCode);
      expect(qr.dataField, 'trackingNo');
      expect(qr.data, isNotEmpty,
          reason: 'a literal fallback drives the headless/no-row canvas');
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(packingSlipDefinition()), isEmpty);
    });
  });
}
