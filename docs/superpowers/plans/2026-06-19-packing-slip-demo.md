# Packing Slip Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `makbuz` tab in the playground with a real, rich single-shipment **packing slip / delivery note** demo (two-column Ship-To/Bill-To header, QR tracking code, items grouped into boxes with per-box subtotals + grand totals, signature footer).

**Architecture:** A new `*_sample.dart` (schema + `ReportDefinition`) and `rendered_*_example.dart` (sample data + one-call render through the public engine), wired into `main.dart` as a `_DesignerTab` — exactly mirroring the existing invoice / nested-list / barcode sample trio. Structurally Shipment ▸ Box ▸ Item, the same nested-scope path the nested-list tab already proves. Public API only (`package:jet_print/jet_print.dart`); **no engine changes**.

**Tech Stack:** Dart / Flutter, `package:jet_print` (reified band model — spec 024), `flutter gen-l10n` for tab strings, `flutter_test`.

## Global Constraints

- **Public API only.** Every new file imports `package:jet_print/jet_print.dart` and nothing from `package:jet_print/src/...` *except* the two test files, which may reach into `src/rendering/frame/primitive.dart` (`TextRunPrimitive`) and `src/rendering/text/text_measurer.dart` (`TextLine`) for the rendered-run proof — exactly as `nested_list_definition_test.dart` does.
- **No engine changes.** No edits under `packages/`. If a task seems to need one, stop and re-scope.
- **Single shipment.** Master data is a list with exactly one shipment map.
- **Stored measures only:** `qtyShipped` (integer) and `lineWeight` (double). Every subtotal/total is computed live via inline aggregates — never stored.
- **Declared schema is mandatory on the data source.** Build the source with `fields: shipmentSchema.fields` so nested `List<Map>` columns are typed as collections; without it the descend-path aggregates silently render 0 (the lesson baked into the nested-list sample).
- **Deterministic sample data.** No RNG, no `DateTime.now()` — stable output so golden/value tests can derive expected sums from the same constants.
- **Run all commands from the app dir:** `apps/jet_print_playground`. Run `git` from the repo root (`/Users/ahmeturel/Projects/oss/jet-print`).
- **Number formats:** units `#,##0`; weight `#,##0.000` (kg, 3 decimals); box count `#,##0`.

---

## File Structure

- **Create** `apps/jet_print_playground/lib/packing_slip_sample.dart` — `const JetDataSchema shipmentSchema` + `ReportDefinition packingSlipDefinition()`.
- **Create** `apps/jet_print_playground/lib/rendered_packing_slip_example.dart` — `kSampleShipment`, `packingSlipDataSource()`, `renderPackingSlipDefinition(...)`.
- **Create** `apps/jet_print_playground/test/packing_slip_definition_test.dart` — structure + `validate()` empty.
- **Create** `apps/jet_print_playground/test/rendered_packing_slip_example_test.dart` — clean render + live totals equal data sums.
- **Modify** `apps/jet_print_playground/lib/l10n/app_en.arb`, `app_de.arb`, `app_tr.arb` — replace `tabReceipt` with `tabPackingSlip`; then regenerate `lib/l10n/app_localizations*.dart` via `flutter gen-l10n`.
- **Modify** `apps/jet_print_playground/lib/main.dart` — import the new sample + render; replace the `_comingSoon('makbuz', …)` line with a live `ShadTab` `_DesignerTab`.

---

## Task 1: Schema + report definition

**Files:**
- Create: `apps/jet_print_playground/lib/packing_slip_sample.dart`
- Test: `apps/jet_print_playground/test/packing_slip_definition_test.dart`

**Interfaces:**
- Produces:
  - `const JetDataSchema shipmentSchema` — master fields `shipmentNo, shipDate, orderNo, carrier, trackingNo, shipToName, shipToAddress, billToName, billToAddress` (all `JetFieldType.string` except `shipDate` = `JetFieldType.dateTime`) plus `boxes` (`JetFieldType.collection`) → fields `boxNo, dimensions` (string) + `items` (`JetFieldType.collection`) → fields `sku, description, attributes, lotNo` (string), `qtyShipped` (`JetFieldType.integer`), `lineWeight` (`JetFieldType.double`).
  - `ReportDefinition packingSlipDefinition()` — root `DetailScope(id:'root')` with one `GroupLevel(id:'shipment', key: r'$F{shipmentNo}')` (header + grand-total footer), a `boxes` `NestedScope` containing a per-box detail band (`id:'boxRow'`), an `items` `NestedScope` (per-item detail band `id:'itemRow'` + box-subtotal footer), page furniture, and a `summary` band with the signature footer.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/packing_slip_definition_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/jet_print_playground && flutter test test/packing_slip_definition_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'jet_print_playground' ... packing_slip_sample.dart` / `shipmentSchema` undefined (file not created yet).

- [ ] **Step 3: Create the sample file**

Create `apps/jet_print_playground/lib/packing_slip_sample.dart`:

```dart
/// The playground's packing-slip sample: a single-shipment **delivery note** —
/// **Shipment ▸ Box ▸ Item** — authored entirely through the library's public
/// API (`package:jet_print/jet_print.dart`), the way an external consumer would.
///
/// Structurally it reuses the reified band model's nesting (spec 024) the way
/// the nested-list sample does, but dresses it as a real packing slip: a
/// two-column Ship-To / Bill-To header with a scannable **QR tracking code**
/// (spec 036), items grouped into **boxes** with per-box subtotals, grand
/// totals, and a once-at-end signature footer.
///
/// Only `qtyShipped` and `lineWeight` are stored; every subtotal/total is a
/// live inline aggregate: the box-subtotal footer folds its own items
/// (`SUM($F{qtyShipped})`, spec 029), and the shipment footer descends
/// [boxes, items] for units/weight and [boxes] for the box `COUNT` (spec 033).
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// The shipment data structure: master fields plus a nested `boxes` collection,
/// each box carrying its own nested `items` collection (master/detail/detail).
/// Attach it via `dataSchema:`.
const JetDataSchema shipmentSchema = JetDataSchema(
  name: 'Shipment',
  fields: <FieldDef>[
    FieldDef('shipmentNo', type: JetFieldType.string),
    FieldDef('shipDate', type: JetFieldType.dateTime),
    FieldDef('orderNo', type: JetFieldType.string),
    FieldDef('carrier', type: JetFieldType.string),
    FieldDef('trackingNo', type: JetFieldType.string),
    FieldDef('shipToName', type: JetFieldType.string),
    FieldDef('shipToAddress', type: JetFieldType.string),
    FieldDef('billToName', type: JetFieldType.string),
    FieldDef('billToAddress', type: JetFieldType.string),
    FieldDef(
      'boxes',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('boxNo', type: JetFieldType.string),
        FieldDef('dimensions', type: JetFieldType.string),
        FieldDef(
          'items',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('sku', type: JetFieldType.string),
            FieldDef('description', type: JetFieldType.string),
            FieldDef('attributes', type: JetFieldType.string),
            FieldDef('lotNo', type: JetFieldType.string),
            FieldDef('qtyShipped', type: JetFieldType.integer),
            FieldDef('lineWeight', type: JetFieldType.double),
          ],
        ),
      ],
    ),
  ],
);

/// A muted grey used for captions and secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// The packing-slip report authored in the reified band model (spec 024).
ReportDefinition packingSlipDefinition() => const ReportDefinition(
      name: 'Packing Slip',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'runningTitle',
              bounds: JetRect(x: 0, y: 2, width: 300, height: 14),
              text: 'PACKING SLIP',
              style: JetTextStyle(
                  fontSize: 9, color: _grey, weight: JetFontWeight.bold),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'pageNumber',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 14),
              text: 'Page',
              style: JetTextStyle(
                  fontSize: 9, color: _grey, align: JetTextAlign.right),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        summary: Band(
          id: 'summary',
          type: BandType.summary,
          height: 70,
          elements: <ReportElement>[
            TextElement(
              id: 'receivedHeading',
              bounds: JetRect(x: 0, y: 4, width: 300, height: 14),
              text: 'Received in good condition:',
              style: JetTextStyle(weight: JetFontWeight.bold),
            ),
            // Three signature rules drawn as thin stroked rectangles.
            ShapeElement(
              id: 'sigRule',
              bounds: JetRect(x: 0, y: 46, width: 200, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(stroke: _grey, strokeWidth: 0.75),
            ),
            TextElement(
              id: 'sigCaption',
              bounds: JetRect(x: 0, y: 50, width: 200, height: 10),
              text: 'Signature',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            ShapeElement(
              id: 'nameRule',
              bounds: JetRect(x: 230, y: 46, width: 160, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(stroke: _grey, strokeWidth: 0.75),
            ),
            TextElement(
              id: 'nameCaption',
              bounds: JetRect(x: 230, y: 50, width: 160, height: 10),
              text: 'Printed name',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            ShapeElement(
              id: 'dateRule',
              bounds: JetRect(x: 410, y: 46, width: 128, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(stroke: _grey, strokeWidth: 0.75),
            ),
            TextElement(
              id: 'dateCaption',
              bounds: JetRect(x: 410, y: 50, width: 128, height: 10),
              text: 'Date received',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'shipment',
              name: 'shipment',
              key: r'$F{shipmentNo}',
              keepTogether: false,
              header: Band(
                id: 'shipmentHeader',
                type: BandType.groupHeader,
                height: 124,
                elements: <ReportElement>[
                  // --- Ship-To block (left) ---
                  TextElement(
                    id: 'shipToLabel',
                    bounds: JetRect(x: 0, y: 0, width: 250, height: 12),
                    text: 'SHIP TO',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'shipToName',
                    bounds: JetRect(x: 0, y: 14, width: 250, height: 16),
                    text: 'shipToName',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                    expression: r'$F{shipToName}',
                  ),
                  TextElement(
                    id: 'shipToAddress',
                    bounds: JetRect(x: 0, y: 32, width: 250, height: 44),
                    text: 'shipToAddress',
                    expression: r'$F{shipToAddress}',
                  ),
                  // --- Bill-To block (right) ---
                  TextElement(
                    id: 'billToLabel',
                    bounds: JetRect(x: 260, y: 0, width: 200, height: 12),
                    text: 'BILL TO',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'billToName',
                    bounds: JetRect(x: 260, y: 14, width: 200, height: 16),
                    text: 'billToName',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                    expression: r'$F{billToName}',
                  ),
                  TextElement(
                    id: 'billToAddress',
                    bounds: JetRect(x: 260, y: 32, width: 200, height: 44),
                    text: 'billToAddress',
                    expression: r'$F{billToAddress}',
                  ),
                  // --- QR tracking code (top-right) ---
                  BarcodeElement(
                    id: 'trackingQr',
                    bounds: JetRect(x: 474, y: 0, width: 64, height: 64),
                    symbology: BarcodeSymbology.qrCode,
                    // Literal fallback drives the headless/no-row canvas; the
                    // bound field wins whenever a row is present.
                    data: '1Z999AA10123456784',
                    dataField: 'trackingNo',
                  ),
                  TextElement(
                    id: 'trackingCaption',
                    bounds: JetRect(x: 458, y: 66, width: 80, height: 10),
                    text: 'trackingNo',
                    style: JetTextStyle(
                        fontSize: 7, color: _grey, align: JetTextAlign.center),
                    expression: r'$F{trackingNo}',
                  ),
                  // --- Meta row (shipment / order / date / carrier) ---
                  TextElement(
                    id: 'metaShipmentNo',
                    bounds: JetRect(x: 0, y: 88, width: 180, height: 14),
                    text: 'shipmentNo',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                    expression: r'"Shipment: " + $F{shipmentNo}',
                  ),
                  TextElement(
                    id: 'metaOrderNo',
                    bounds: JetRect(x: 190, y: 88, width: 200, height: 14),
                    text: 'orderNo',
                    expression: r'"Order: " + $F{orderNo}',
                  ),
                  TextElement(
                    id: 'metaDate',
                    bounds: JetRect(x: 0, y: 104, width: 180, height: 14),
                    text: 'date',
                    expression: r'"Date: " + $F{shipDate}',
                  ),
                  TextElement(
                    id: 'metaCarrier',
                    bounds: JetRect(x: 190, y: 104, width: 280, height: 14),
                    text: 'carrier',
                    expression: r'"Carrier: " + $F{carrier}',
                  ),
                ],
              ),
              footer: Band(
                id: 'shipmentFooter',
                type: BandType.groupFooter,
                height: 58,
                elements: <ReportElement>[
                  TextElement(
                    id: 'totalBoxesLabel',
                    bounds: JetRect(x: 300, y: 2, width: 130, height: 16),
                    text: 'Total boxes',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'totalBoxes',
                    bounds: JetRect(x: 434, y: 2, width: 104, height: 16),
                    text: 'totalBoxes',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'COUNT($F{boxNo})',
                    format: '#,##0',
                  ),
                  TextElement(
                    id: 'totalUnitsLabel',
                    bounds: JetRect(x: 300, y: 20, width: 130, height: 16),
                    text: 'Total units',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'totalUnits',
                    bounds: JetRect(x: 434, y: 20, width: 104, height: 16),
                    text: 'totalUnits',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{qtyShipped})',
                    format: '#,##0',
                  ),
                  TextElement(
                    id: 'totalWeightLabel',
                    bounds: JetRect(x: 300, y: 38, width: 130, height: 16),
                    text: 'Total weight (kg)',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'totalWeight',
                    bounds: JetRect(x: 434, y: 38, width: 104, height: 16),
                    text: 'totalWeight',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{lineWeight})',
                    format: '#,##0.000',
                  ),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'boxes',
              collectionField: 'boxes',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'boxRow',
                  type: BandType.detail,
                  height: 38,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'boxTitle',
                      bounds: JetRect(x: 0, y: 2, width: 440, height: 16),
                      text: 'boxTitle',
                      style: JetTextStyle(weight: JetFontWeight.bold),
                      expression:
                          r'"Box " + $F{boxNo} + "   ·   " + $F{dimensions}',
                    ),
                    TextElement(
                      id: 'colSku',
                      bounds: JetRect(x: 24, y: 22, width: 78, height: 12),
                      text: 'SKU',
                      style:
                          JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colDescription',
                      bounds: JetRect(x: 104, y: 22, width: 150, height: 12),
                      text: 'Description',
                      style:
                          JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colAttributes',
                      bounds: JetRect(x: 256, y: 22, width: 120, height: 12),
                      text: 'Attributes',
                      style:
                          JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colLot',
                      bounds: JetRect(x: 378, y: 22, width: 70, height: 12),
                      text: 'Lot',
                      style:
                          JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colQty',
                      bounds: JetRect(x: 450, y: 22, width: 34, height: 12),
                      text: 'Qty',
                      style: JetTextStyle(
                          fontSize: 9,
                          align: JetTextAlign.right,
                          weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colWeight',
                      bounds: JetRect(x: 486, y: 22, width: 52, height: 12),
                      text: 'Weight',
                      style: JetTextStyle(
                          fontSize: 9,
                          align: JetTextAlign.right,
                          weight: JetFontWeight.bold),
                    ),
                  ],
                )),
                NestedScope(DetailScope(
                  id: 'items',
                  collectionField: 'items',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'itemRow',
                      type: BandType.detail,
                      height: 16,
                      elements: <ReportElement>[
                        TextElement(
                          id: 'itemSku',
                          bounds: JetRect(x: 24, y: 1, width: 78, height: 14),
                          text: 'sku',
                          expression: r'$F{sku}',
                        ),
                        TextElement(
                          id: 'itemDescription',
                          bounds: JetRect(x: 104, y: 1, width: 150, height: 14),
                          text: 'description',
                          expression: r'$F{description}',
                        ),
                        TextElement(
                          id: 'itemAttributes',
                          bounds: JetRect(x: 256, y: 1, width: 120, height: 14),
                          text: 'attributes',
                          style: JetTextStyle(fontSize: 9, color: _grey),
                          expression: r'$F{attributes}',
                        ),
                        TextElement(
                          id: 'itemLot',
                          bounds: JetRect(x: 378, y: 1, width: 70, height: 14),
                          text: 'lotNo',
                          style: JetTextStyle(fontSize: 9),
                          expression: r'$F{lotNo}',
                        ),
                        TextElement(
                          id: 'itemQty',
                          bounds: JetRect(x: 450, y: 1, width: 34, height: 14),
                          text: 'qtyShipped',
                          style: JetTextStyle(align: JetTextAlign.right),
                          expression: r'$F{qtyShipped}',
                          format: '#,##0',
                        ),
                        TextElement(
                          id: 'itemWeight',
                          bounds: JetRect(x: 486, y: 1, width: 52, height: 14),
                          text: 'lineWeight',
                          style: JetTextStyle(align: JetTextAlign.right),
                          expression: r'$F{lineWeight}',
                          format: '#,##0.000',
                        ),
                      ],
                    )),
                  ],
                  // Same-scope fold over the box's items (spec 029): per-box
                  // unit count + weight. No ScopeTotal needed.
                  footer: Band(
                    id: 'itemsFooter',
                    type: BandType.groupFooter,
                    height: 18,
                    elements: <ReportElement>[
                      TextElement(
                        id: 'boxSubtotalLabel',
                        bounds: JetRect(x: 256, y: 1, width: 190, height: 14),
                        text: 'Box subtotal',
                        style: JetTextStyle(
                            fontSize: 9,
                            align: JetTextAlign.right,
                            color: _grey),
                      ),
                      TextElement(
                        id: 'boxUnits',
                        bounds: JetRect(x: 450, y: 1, width: 34, height: 14),
                        text: 'boxUnits',
                        style: JetTextStyle(
                            align: JetTextAlign.right,
                            weight: JetFontWeight.bold),
                        expression: r'SUM($F{qtyShipped})',
                        format: '#,##0',
                      ),
                      TextElement(
                        id: 'boxWeight',
                        bounds: JetRect(x: 486, y: 1, width: 52, height: 14),
                        text: 'boxWeight',
                        style: JetTextStyle(
                            align: JetTextAlign.right,
                            weight: JetFontWeight.bold),
                        expression: r'SUM($F{lineWeight})',
                        format: '#,##0.000',
                      ),
                    ],
                  ),
                )),
              ],
            )),
          ],
        ),
      ),
    );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/jet_print_playground && flutter test test/packing_slip_definition_test.dart`
Expected: PASS (all 6 tests green). If `validate()` returns diagnostics, read them — the most likely cause is a band-type mismatch (e.g. a per-row band that isn't `BandType.detail`); fix the definition to match the structure above, do not relax the test.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/packing_slip_sample.dart apps/jet_print_playground/test/packing_slip_definition_test.dart
git commit -m "feat(playground): packing-slip schema + report definition

Shipment ▸ Box ▸ Item delivery note authored on the public API: two-column
Ship-To/Bill-To header with a QR tracking code, per-box subtotal footers, and
inline grand totals (COUNT boxes, SUM units, SUM weight). Pristine under the
validator.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Sample data + render entry point

**Files:**
- Create: `apps/jet_print_playground/lib/rendered_packing_slip_example.dart`
- Test: `apps/jet_print_playground/test/rendered_packing_slip_example_test.dart`

**Interfaces:**
- Consumes: `shipmentSchema`, `packingSlipDefinition()` from Task 1.
- Produces:
  - `const List<Map<String, Object?>> kSampleShipment` — a one-element list (single shipment) with a `boxes` list (3 boxes), each with an `items` list (2/3/2 items). The single source of truth tests derive expected sums from.
  - `JetDataSource packingSlipDataSource()` — `JetInMemoryDataSource(kSampleShipment, fields: shipmentSchema.fields)`.
  - `RenderedReport renderPackingSlipDefinition({ReportDefinition? definition, JetDataSource? source, List<JetFontFamily> fonts})`.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/rendered_packing_slip_example_test.dart`:

```dart
// Rendered packing-slip example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the single shipment fills
// cleanly and that the live per-box subtotals and grand totals equal the sums
// of the SAME sample data the render fills — so the proof and the render can
// never silently drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation imports for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. nested_list_definition_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_packing_slip_example.dart';

void main() {
  group('rendered packing-slip example', () {
    test('ships one shipment with three boxes of items', () {
      expect(kSampleShipment, hasLength(1));
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();
      expect(boxes, hasLength(3));
      // Every item carries the two stored measures and a lot number.
      for (final Map<String, Object?> box in boxes) {
        for (final Map<String, Object?> item
            in (box['items']! as List<Object?>).cast()) {
          expect(item['qtyShipped'], isA<int>());
          expect(item['lineWeight'], isA<num>());
          expect(item['lotNo'], isA<String>());
        }
      }
    });

    test('renders the shipment cleanly (no error diagnostics)', () {
      final RenderedReport report = renderPackingSlipDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason: 'a fully-bound packing slip + matching data renders cleanly',
      );
    });

    test('per-box subtotals equal the live data sums', () {
      final RenderedReport report = renderPackingSlipDefinition();
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();

      final List<String> expectedUnits = <String>[
        for (final Map<String, Object?> box in boxes)
          NumberFormat('#,##0').format(_boxUnits(box)),
      ];
      final List<String> expectedWeight = <String>[
        for (final Map<String, Object?> box in boxes)
          NumberFormat('#,##0.000').format(_boxWeight(box)),
      ];
      expect(_runsForId(report, 'boxUnits'), expectedUnits,
          reason: 'each box footer unit count equals its items’ qty sum');
      expect(_runsForId(report, 'boxWeight'), expectedWeight,
          reason: 'each box footer weight equals its items’ weight sum');
    });

    test('grand totals equal the whole-shipment live sums', () {
      final RenderedReport report = renderPackingSlipDefinition();
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();

      final int totalUnits =
          boxes.fold<int>(0, (int s, Map<String, Object?> b) => s + _boxUnits(b));
      final double totalWeight = boxes.fold<double>(
          0, (double s, Map<String, Object?> b) => s + _boxWeight(b));

      expect(_runsForId(report, 'totalBoxes'),
          <String>[NumberFormat('#,##0').format(boxes.length)]);
      expect(_runsForId(report, 'totalUnits'),
          <String>[NumberFormat('#,##0').format(totalUnits)]);
      expect(_runsForId(report, 'totalWeight'),
          <String>[NumberFormat('#,##0.000').format(totalWeight)]);
    });
  });
}

int _boxUnits(Map<String, Object?> box) => (box['items']! as List<Object?>)
    .cast<Map<String, Object?>>()
    .fold<int>(0, (int s, Map<String, Object?> i) => s + (i['qtyShipped']! as int));

double _boxWeight(Map<String, Object?> box) => (box['items']! as List<Object?>)
    .cast<Map<String, Object?>>()
    .fold<double>(
        0, (double s, Map<String, Object?> i) => s + (i['lineWeight']! as num));

/// The rendered text runs of [elementId], in paint order across all pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/jet_print_playground && flutter test test/rendered_packing_slip_example_test.dart`
Expected: FAIL — `rendered_packing_slip_example.dart` / `kSampleShipment` undefined (file not created yet).

- [ ] **Step 3: Create the rendered-example file**

Create `apps/jet_print_playground/lib/rendered_packing_slip_example.dart`:

```dart
/// Real data for the packing-slip sample, plus the one-call render through the
/// public engine — the consumer side of the Shipment ▸ Box ▸ Item demo, all
/// through `package:jet_print/jet_print.dart` only.
///
/// One deterministic shipment of three boxes (2 / 3 / 2 items). The only stored
/// measures are each item's `qtyShipped` and `lineWeight`; every subtotal/total
/// is computed live (per-box footer folds its items; the shipment footer
/// descends [boxes, items] and counts [boxes]). The declared schema
/// (`shipmentSchema.fields`) is passed to the data source so nested `List<Map>`
/// columns are typed as collections and descend paths resolve correctly.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'packing_slip_sample.dart';

/// The single sample shipment — the source of truth the data source and tests
/// both read, so the rendered totals and the expected sums can never drift.
const List<Map<String, Object?>> kSampleShipment = <Map<String, Object?>>[
  <String, Object?>{
    'shipmentNo': 'SH-20488',
    'shipDate': '2026-06-19',
    'orderNo': 'SO-1042',
    'carrier': 'UPS Standard',
    'trackingNo': '1Z999AA10123456784',
    'shipToName': 'Globex SARL',
    'shipToAddress': 'Attn: Receiving Dock\n12 Rue de l’Industrie\n69007 Lyon\nFrance',
    'billToName': 'Globex SARL — Accounts Payable',
    'billToAddress': 'BP 4471\n69356 Lyon CEDEX 07\nFrance',
    'boxes': <Map<String, Object?>>[
      <String, Object?>{
        'boxNo': 'B-01',
        'dimensions': '40 × 30 × 25 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-1001',
            'description': 'Wireless Mouse',
            'attributes': 'Color: Black',
            'lotNo': 'LOT-A1',
            'qtyShipped': 4,
            'lineWeight': 0.480,
          },
          <String, Object?>{
            'sku': 'SKU-1002',
            'description': 'USB-C Cable 2m',
            'attributes': 'Length: 2m',
            'lotNo': 'LOT-A2',
            'qtyShipped': 10,
            'lineWeight': 0.350,
          },
        ],
      },
      <String, Object?>{
        'boxNo': 'B-02',
        'dimensions': '60 × 40 × 30 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-2001',
            'description': 'Mechanical Keyboard',
            'attributes': 'Layout: US',
            'lotNo': 'LOT-B1',
            'qtyShipped': 2,
            'lineWeight': 2.400,
          },
          <String, Object?>{
            'sku': 'SKU-2002',
            'description': 'Laptop Stand',
            'attributes': 'Color: Silver',
            'lotNo': 'LOT-B2',
            'qtyShipped': 3,
            'lineWeight': 1.200,
          },
          <String, Object?>{
            'sku': 'SKU-2003',
            'description': 'Webcam 1080p',
            'attributes': 'FOV: 90°',
            'lotNo': 'LOT-B3',
            'qtyShipped': 5,
            'lineWeight': 0.250,
          },
        ],
      },
      <String, Object?>{
        'boxNo': 'B-03',
        'dimensions': '30 × 20 × 15 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-3001',
            'description': 'Desk Lamp LED',
            'attributes': 'Color: White',
            'lotNo': 'LOT-C1',
            'qtyShipped': 1,
            'lineWeight': 0.900,
          },
          <String, Object?>{
            'sku': 'SKU-3002',
            'description': 'HDMI Adapter',
            'attributes': 'Type: 4K',
            'lotNo': 'LOT-C2',
            'qtyShipped': 8,
            'lineWeight': 0.060,
          },
        ],
      },
    ],
  },
];

/// The single sample shipment as an in-memory data source, matching
/// [shipmentSchema]. The declared `fields:` is required so nested `List<Map>`
/// columns are typed as collections (else descend-path aggregates render 0).
JetDataSource packingSlipDataSource() =>
    JetInMemoryDataSource(kSampleShipment, fields: shipmentSchema.fields);

/// Renders [packingSlipDefinition] over [packingSlipDataSource] through the
/// native [JetReportEngine.renderDefinition] path — the same single call the
/// designer tab's preview uses. [definition] defaults to the bundled sample so
/// the designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderPackingSlipDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? packingSlipDefinition(),
      source ?? packingSlipDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(shipmentSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares, top-level and nested (so
/// collection-scoped bindings like `$F{qtyShipped}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/jet_print_playground && flutter test test/rendered_packing_slip_example_test.dart`
Expected: PASS (4 tests green). The expected per-box sums are units `4`/`10` → `14`, `2`/`3`/`5` → `10`, `1`/`8` → `9`; weights `0.830`, `3.850`, `0.960`; grand `Total boxes 3`, `Total units 33`, `Total weight 5.640`. If `boxUnits`/`totalUnits` come back empty or `0`, the data source is missing `fields: shipmentSchema.fields` — re-check Step 3.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/rendered_packing_slip_example.dart apps/jet_print_playground/test/rendered_packing_slip_example_test.dart
git commit -m "feat(playground): packing-slip sample data + render entry point

One deterministic 3-box shipment plus the one-call renderDefinition wrapper;
tests prove per-box subtotals and grand totals equal the live data sums.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Localized tab label

**Files:**
- Modify: `apps/jet_print_playground/lib/l10n/app_en.arb`
- Modify: `apps/jet_print_playground/lib/l10n/app_de.arb`
- Modify: `apps/jet_print_playground/lib/l10n/app_tr.arb`
- Regenerates: `apps/jet_print_playground/lib/l10n/app_localizations*.dart` (via `flutter gen-l10n`)

**Interfaces:**
- Produces: `AppLocalizations.tabPackingSlip` getter (en "Packing slip", de "Lieferschein", tr "İrsaliye"). Removes the now-unused `tabReceipt`.

- [ ] **Step 1: Edit the English template ARB**

In `apps/jet_print_playground/lib/l10n/app_en.arb`, replace the `tabReceipt` block (lines 29–32):

```json
  "tabReceipt": "Receipt",
  "@tabReceipt": {
    "description": "Tab label for the receipt report demo (placeholder)."
  },
```

with:

```json
  "tabPackingSlip": "Packing slip",
  "@tabPackingSlip": {
    "description": "Tab label for the packing-slip / delivery-note designer demo."
  },
```

- [ ] **Step 2: Edit the German ARB**

In `apps/jet_print_playground/lib/l10n/app_de.arb`, change line 9 from:

```json
  "tabReceipt": "Beleg",
```

to:

```json
  "tabPackingSlip": "Lieferschein",
```

- [ ] **Step 3: Edit the Turkish ARB**

In `apps/jet_print_playground/lib/l10n/app_tr.arb`, change line 9 from:

```json
  "tabReceipt": "Makbuz",
```

to:

```json
  "tabPackingSlip": "İrsaliye",
```

- [ ] **Step 4: Regenerate the localizations**

Run: `cd apps/jet_print_playground && flutter gen-l10n`
Expected: no errors; `lib/l10n/app_localizations.dart` now declares `String get tabPackingSlip;` and no longer declares `tabReceipt` (and the `_en/_de/_tr` files update to match).

- [ ] **Step 5: Verify the generated getter exists**

Run: `grep -n "tabPackingSlip\|tabReceipt" apps/jet_print_playground/lib/l10n/app_localizations.dart`
Expected: one or more `tabPackingSlip` matches, zero `tabReceipt` matches.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/l10n
git commit -m "feat(playground): replace Receipt tab string with Packing slip

en 'Packing slip' / de 'Lieferschein' / tr 'İrsaliye'; regenerated l10n.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire the tab into the playground shell

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`

**Interfaces:**
- Consumes: `packingSlipDefinition()` + `shipmentSchema` (Task 1), `renderPackingSlipDefinition` (Task 2), `AppLocalizations.tabPackingSlip` (Task 3).

- [ ] **Step 1: Add the imports**

In `apps/jet_print_playground/lib/main.dart`, add to the import block (after the existing `import 'nested_list_sample.dart';` group — keep imports alphabetical within their cluster):

```dart
import 'packing_slip_sample.dart';
import 'rendered_packing_slip_example.dart';
```

- [ ] **Step 2: Replace the placeholder tab with a live designer tab**

In `apps/jet_print_playground/lib/main.dart`, replace this single line (currently line 241):

```dart
                _comingSoon('makbuz', l10n.tabReceipt, LucideIcons.receipt),
```

with:

```dart
                ShadTab<String>(
                  value: 'makbuz',
                  leading: const Icon(LucideIcons.package, size: 16),
                  expandContent: true,
                  // A live designer over a single shipment — Shipment ▸ Box ▸
                  // Item with a two-column address header, a QR tracking code,
                  // per-box subtotals and grand totals (packing_slip_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: packingSlipDefinition(),
                      dataSchema: shipmentSchema,
                      renderReport: (ReportDefinition def) =>
                          renderPackingSlipDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabPackingSlip),
                ),
```

- [ ] **Step 3: Verify it analyzes clean**

Run: `cd apps/jet_print_playground && flutter analyze`
Expected: "No issues found!" In particular, no reference to the removed `l10n.tabReceipt` remains, and `_comingSoon` may now be unused — if `flutter analyze` flags `_comingSoon` as unused, delete the `_comingSoon` method (lines ~145–152) since the packing-slip tab was its last caller.

- [ ] **Step 4: Run the full playground test suite**

Run: `cd apps/jet_print_playground && flutter test`
Expected: all tests pass, including `app_consumes_library_test.dart` and the two new test files. If `_comingSoon` was removed and the `comingSoon` l10n string is now unused, that's fine — leave the string (no test asserts on it; removing it is out of scope).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart
git commit -m "feat(playground): wire the packing-slip tab (replaces placeholder)

The makbuz tab is now a live designer over the single-shipment packing slip,
replacing the coming-soon card; package icon + İrsaliye/Lieferschein/Packing
slip label.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full-repo verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole repo**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter analyze` (or `melos run analyze` if the repo defines it — check `melos.yaml`).
Expected: "No issues found!" across packages + app.

- [ ] **Step 2: Run the full test suite (library + app)**

Run the library tests: `cd packages/jet_print && flutter test`
Run the app tests: `cd apps/jet_print_playground && flutter test`
Expected: all green. The engine arch/encapsulation tests (run from the package root) confirm no `src/` leakage from the new app files (the app's two test files reach into `src/` deliberately and are not under `packages/`, so they're outside that boundary check).

- [ ] **Step 3: Manual GUI smoke (optional but recommended)**

Run: `cd apps/jet_print_playground && flutter run -d macos`
Confirm: the **İrsaliye / Lieferschein / Packing slip** tab opens a live designer; the preview shows the two-column Ship-To/Bill-To header, a scannable QR, three boxes with per-box subtotals, the grand-total footer (Total boxes 3 / Total units 33 / Total weight 5.640), and the signature footer; Export PDF and Print work as on other tabs.

---

## Self-Review

**1. Spec coverage** (against `docs/superpowers/specs/2026-06-19-packing-slip-demo-design.md`):
- Two-column Ship-To/Bill-To header → Task 1 `shipmentHeader` (shipTo* / billTo* blocks). ✓
- QR tracking code → Task 1 `trackingQr` (`BarcodeSymbology.qrCode`, `dataField: 'trackingNo'`); test asserts it. ✓
- Per-box subtotals → Task 1 `itemsFooter` (`boxUnits`/`boxWeight`); Task 2 value test. ✓
- Grand totals (COUNT boxes, SUM units, SUM weight) → Task 1 `shipmentFooter`; Task 2 value test. ✓
- Item attributes + lot numbers → schema `attributes`/`lotNo`, `itemRow` columns + data. ✓
- Signature/received-by footer → Task 1 `summary` band (rules + captions). ✓
- Single shipment, stored measures only, declared schema on source → Task 2 `kSampleShipment` (1 row) + `fields: shipmentSchema.fields`. ✓
- Component files + tests + main wiring + l10n → Tasks 1–4. ✓
- Out-of-scope items (batch, conditional formatting, attributes sub-collection) → not implemented. ✓

**2. Placeholder scan:** No "TBD/TODO"; every code/test step shows full content; commands have expected output. ✓

**3. Type consistency:** Element ids referenced in tests (`trackingQr`, `boxUnits`, `boxWeight`, `totalBoxes`, `totalUnits`, `totalWeight`) match the definition in Task 1. Producer/consumer names (`shipmentSchema`, `packingSlipDefinition`, `kSampleShipment`, `packingSlipDataSource`, `renderPackingSlipDefinition`, `tabPackingSlip`) are identical across tasks. `JetInMemoryDataSource(..., fields:)`, `RenderOptions(locale/knownFields/fonts)`, `BarcodeElement(symbology/data/dataField)`, `ShapeElement(kind/style)`, `JetBoxStyle(stroke/strokeWidth)` all match the verified public API used by the existing samples. ✓
