/// The playground's sales-ledger sample — a flat, multi-page transaction list
/// authored entirely through the library's public API
/// (`package:jet_print/jet_print.dart`). It is the demo for [JetPagedDataSource]
/// (spec 040): the data is generated on demand, one page at a time, never held
/// whole in memory (see `rendered_ledger_example.dart`).
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// A flat transaction row. `time` is a pre-formatted timestamp string.
const JetDataSchema ledgerSchema = JetDataSchema(
  name: 'Transaction',
  fields: <FieldDef>[
    FieldDef('time', type: JetFieldType.string),
    FieldDef('receiptNo', type: JetFieldType.string),
    FieldDef('item', type: JetFieldType.string),
    FieldDef('qty', type: JetFieldType.integer),
    FieldDef('unitPrice', type: JetFieldType.double),
    FieldDef('amount', type: JetFieldType.double),
    FieldDef('status', type: JetFieldType.string),
  ],
);

/// Muted grey for secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// A thin rule under the header and above the grand total.
const JetColor _rule = JetColor(0xFFB0B0B0);

/// Two-decimal money mask.
const String _money = '#,##0.00';

/// Thousands-grouped integer mask.
const String _int = '#,##0';

/// The sales-ledger report authored in the reified band model (spec 024/040).
ReportDefinition ledgerSampleDefinition() => ReportDefinition(
      name: 'Sales Ledger',
      page: PageFormat.a4Portrait,
      furniture: const PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 538, height: 18),
              text: 'Sales Ledger',
              style: JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
            ),
            // Column headings — repeat on every page via the page header.
            TextElement(
              id: 'hTime',
              bounds: JetRect(x: 0, y: 24, width: 92, height: 12),
              text: 'Time',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hReceipt',
              bounds: JetRect(x: 96, y: 24, width: 66, height: 12),
              text: 'Receipt',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hItem',
              bounds: JetRect(x: 166, y: 24, width: 190, height: 12),
              text: 'Item',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hQty',
              bounds: JetRect(x: 360, y: 24, width: 34, height: 12),
              text: 'Qty',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hAmount',
              bounds: JetRect(x: 398, y: 24, width: 74, height: 12),
              text: 'Amount',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hStatus',
              bounds: JetRect(x: 476, y: 24, width: 62, height: 12),
              text: 'Status',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 38, width: 538, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 18,
          elements: <ReportElement>[
            TextElement(
              id: 'pageNo',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 12),
              text: 'Page',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        summary: const Band(
          id: 'summary',
          type: BandType.summary,
          height: 34,
          elements: <ReportElement>[
            ShapeElement(
              id: 'summaryRule',
              bounds: JetRect(x: 0, y: 4, width: 538, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
            TextElement(
              id: 'countLabel',
              bounds: JetRect(x: 0, y: 10, width: 120, height: 16),
              text: 'Transactions',
              style: JetTextStyle(weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'txnCount',
              bounds: JetRect(x: 124, y: 10, width: 90, height: 16),
              text: 'count',
              style: JetTextStyle(),
              expression: r'COUNT($F{receiptNo})',
              format: _int,
            ),
            TextElement(
              id: 'sumLabel',
              bounds: JetRect(x: 300, y: 10, width: 120, height: 16),
              text: 'Total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'grandSum',
              bounds: JetRect(x: 424, y: 10, width: 114, height: 16),
              text: 'total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'SUM($F{amount})',
              format: _money,
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'txn',
              type: BandType.detail,
              height: 15,
              elements: const <ReportElement>[
                TextElement(
                  id: 'cTime',
                  bounds: JetRect(x: 0, y: 1, width: 92, height: 12),
                  text: 'time',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{time}',
                ),
                TextElement(
                  id: 'cReceipt',
                  bounds: JetRect(x: 96, y: 1, width: 66, height: 12),
                  text: 'receiptNo',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{receiptNo}',
                ),
                TextElement(
                  id: 'cItem',
                  bounds: JetRect(x: 166, y: 1, width: 190, height: 12),
                  text: 'item',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{item}',
                ),
                TextElement(
                  id: 'cQty',
                  bounds: JetRect(x: 360, y: 1, width: 34, height: 12),
                  text: 'qty',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{qty}',
                  format: _int,
                ),
                TextElement(
                  id: 'cAmount',
                  bounds: JetRect(x: 398, y: 1, width: 74, height: 12),
                  text: 'amount',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{amount}',
                  format: _money,
                ),
                TextElement(
                  id: 'cStatus',
                  bounds: JetRect(x: 476, y: 1, width: 62, height: 12),
                  text: 'status',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{status}',
                ),
              ],
            )),
          ],
        ),
      ),
    );
