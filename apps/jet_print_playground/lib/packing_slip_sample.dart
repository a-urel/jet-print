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
                height: 144,
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
                    bounds: JetRect(x: 0, y: 32, width: 250, height: 68),
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
                    bounds: JetRect(x: 260, y: 32, width: 200, height: 68),
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
                    bounds: JetRect(x: 0, y: 108, width: 180, height: 14),
                    text: 'shipmentNo',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                    expression: r'"Shipment: " + $F{shipmentNo}',
                  ),
                  TextElement(
                    id: 'metaOrderNo',
                    bounds: JetRect(x: 190, y: 108, width: 200, height: 14),
                    text: 'orderNo',
                    expression: r'"Order: " + $F{orderNo}',
                  ),
                  TextElement(
                    id: 'metaDate',
                    bounds: JetRect(x: 0, y: 124, width: 180, height: 14),
                    text: 'date',
                    expression: r'"Date: " + $F{shipDate}',
                  ),
                  TextElement(
                    id: 'metaCarrier',
                    bounds: JetRect(x: 190, y: 124, width: 280, height: 14),
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
