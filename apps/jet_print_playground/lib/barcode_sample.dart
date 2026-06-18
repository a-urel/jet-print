/// The playground's barcode sample: a **2-column product-label sheet** authored
/// entirely through the library's public API (`package:jet_print/jet_print.dart`),
/// the way an external consumer would.
///
/// Built on the same engine pieces as the address-label sheet (spec 034 native
/// multi-column layout) plus the barcode element (spec 036): the detail band
/// carries a [ColumnLayout], so a single label cell is authored once — in
/// cell-local coordinates — and the engine repeats it across the grid in
/// horizontal print order (left-to-right, wrapping down, then to the next page).
/// Each cell shows a product name and a real, scannable **EAN-13** barcode bound
/// to the row's product number; the barcode's human-readable text echoes that
/// number under the bars.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// How many label cells sit across one row — the grid's [ColumnLayout.columnCount].
const int barcodeColumns = 2;

// --- Cell geometry (cell-local; the grid offsets each repeat) -----------------
//
// A4 portrait content area ≈ 538 × 785 pt. The grid is [barcodeColumns] cells of
// [_cellWidth] separated by [_columnSpacing]: 2 × 260 + 18 = 538 ≤ 538, so it
// fits the body. Seven [_rowHeight]-tall rows (7 × 112 = 784 ≤ 785) fill the
// page height, so each A4 page carries 7 × [barcodeColumns] = 14 labels.

/// Drawn width of a single label tile — the grid's [ColumnLayout.columnWidth].
const double _cellWidth = 260;

/// Horizontal gutter between cells — the grid's [ColumnLayout.columnSpacing].
const double _columnSpacing = 18;

/// Height of one label row (one detail-band instance).
const double _rowHeight = 112;

/// Vertical gap between label rows — the grid's [ColumnLayout.rowSpacing].
const double _rowSpacing = 0;

/// Inner padding from the tile's border to its content.
const double _pad = 12;

/// The flat data schema one product record satisfies: the display [product] name
/// and its [sku] (a valid 13-digit EAN-13 number), one record per label cell.
/// Attach via `dataSchema:`.
final JetDataSchema barcodeSchema = JetDataSchema(
  name: 'Products',
  fields: <FieldDef>[
    FieldDef('product', type: JetFieldType.string),
    FieldDef('sku', type: JetFieldType.string),
  ],
);

/// Builds the elements for **one** product label cell, in cell-local coordinates
/// (the grid repeats this cell across the columns): a light border tile, the
/// product name bound to `product`, and an [BarcodeElement] encoding the row's
/// `sku` as a scannable EAN-13 with the number printed underneath.
List<ReportElement> _cellElements() => <ReportElement>[
      // The cut-tile border (data-blind; drawn for every cell slot).
      ShapeElement(
        id: 'border',
        bounds: JetRect(x: 0, y: 2, width: _cellWidth, height: _rowHeight - 6),
        kind: ShapeKind.rectangle,
        style:
            const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
      ),
      TextElement(
        id: 'product',
        bounds:
            JetRect(x: _pad, y: 12, width: _cellWidth - _pad * 2, height: 18),
        text: 'Product',
        style: const JetTextStyle(fontSize: 12, weight: JetFontWeight.bold),
        expression: '\$F{product}',
      ),
      // A real EAN-13 retail barcode bound to the row's product number; its
      // human-readable text prints the digits under the bars (showText).
      //
      // Symbology is left at [BarcodeSymbology.auto] (the default for new
      // elements): the engine infers EAN-13 from the 13-digit numeric value at
      // fill time. The literal fallback below — a valid EAN-13 — drives the
      // design-time canvas, so auto-inference shows a real EAN-13 there too.
      BarcodeElement(
        id: 'barcode',
        bounds: JetRect(
          x: _pad,
          y: 36,
          width: _cellWidth - _pad * 2,
          height: _rowHeight - 36 - 8,
        ),
        symbology: BarcodeSymbology.auto,
        // Literal fallback (a valid EAN-13) for the headless/no-row case; the
        // bound field below wins whenever a row is present.
        data: '4006381333931',
        dataField: 'sku',
      ),
    ];

/// The 2-column product-label sheet, authored in the reified band model with a
/// native [ColumnLayout].
///
/// Furniture-free (labels carry no page header/footer): the body's root
/// [DetailScope] iterates the flat product rows, and its single per-row `detail`
/// band — one label cell, [_rowHeight] tall — carries the [ColumnLayout] that
/// repeats it across [barcodeColumns] columns. The engine places the cells in
/// horizontal order and wraps down the page, then to the next page.
ReportDefinition barcodeSampleDefinition() => ReportDefinition(
      name: 'Product labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'productLabel',
              type: BandType.detail,
              height: _rowHeight,
              columnLayout: const ColumnLayout(
                columnCount: barcodeColumns,
                columnWidth: _cellWidth,
                columnSpacing: _columnSpacing,
                rowSpacing: _rowSpacing,
              ),
              elements: _cellElements(),
            )),
          ],
        ),
      ),
    );
