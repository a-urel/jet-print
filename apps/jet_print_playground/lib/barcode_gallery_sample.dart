/// A **barcode-symbology gallery**: a single A4 page that draws every newly
/// wired 1D symbology side by side, each with its friendly name and a real,
/// scannable sample value (the human-readable text prints under the bars).
///
/// Unlike the product-label sheet (`barcode_sample.dart`), the symbology is
/// fixed per [BarcodeElement] — it is a compile-time enum, not a bindable
/// field — so the codes cannot be varied by a data-driven [ColumnLayout] that
/// repeats one band. The gallery is therefore authored as a **static** grid:
/// one detail band, rendered exactly once (the data source carries a single
/// empty row), holding all twelve cells at fixed positions.
///
/// Authored entirely through the library's public API, the way a consumer
/// would. Field/label text is illustrative sample data, intentionally not
/// localized.
library;

import 'package:jet_print/jet_print.dart';

/// One gallery cell: the symbology to draw, its display [label], and a sample
/// [value] that is valid for that symbology (so the code actually encodes).
typedef _GalleryEntry = ({BarcodeSymbology symbology, String label, String value});

/// The twelve symbologies wired in the cheap-add and free-win batches, each
/// paired with a value known to be valid for it (see the encoder tests).
const List<_GalleryEntry> _gallery = <_GalleryEntry>[
  (symbology: BarcodeSymbology.code93, label: 'Code 93', value: 'CODE-93'),
  (symbology: BarcodeSymbology.codabar, label: 'Codabar', value: '1234567'),
  (symbology: BarcodeSymbology.itf, label: 'Interleaved 2 of 5', value: '1234'),
  (
    symbology: BarcodeSymbology.gs128,
    label: 'GS1-128 (EAN-128)',
    value: '(01)00012345678905'
  ),
  (symbology: BarcodeSymbology.upcE, label: 'UPC-E', value: '01234565'),
  (symbology: BarcodeSymbology.ean2, label: 'EAN-2 supplement', value: '12'),
  (symbology: BarcodeSymbology.ean5, label: 'EAN-5 supplement', value: '12345'),
  (symbology: BarcodeSymbology.postnet, label: 'POSTNET', value: '55555'),
  (symbology: BarcodeSymbology.itf16, label: 'ITF-16', value: '123456789012345'),
  (symbology: BarcodeSymbology.isbn, label: 'ISBN', value: '9780306406157'),
  (symbology: BarcodeSymbology.telepen, label: 'Telepen', value: 'ABC123'),
  (
    symbology: BarcodeSymbology.rm4scc,
    label: 'RM4SCC (Royal Mail)',
    value: 'LE28HE'
  ),
];

// --- Grid geometry (absolute; A4 portrait content area ≈ 538 × 785 pt) --------

/// Cells per row.
const int _columns = 2;

/// Drawn width of one cell.
const double _cellWidth = 260;

/// Horizontal gutter between cells (2 × 260 + 18 = 538 ≤ 538).
const double _columnSpacing = 18;

/// Height of one cell.
const double _cellHeight = 118;

/// Vertical gutter between cell rows.
const double _rowSpacing = 6;

/// Top of the first cell row, below the page heading.
const double _gridTop = 34;

/// Inner padding from a cell's border to its content.
const double _pad = 8;

/// The gallery needs no real fields — every value is a literal — so the schema
/// is empty. A single (empty) row drives the one render of the detail band.
final JetDataSchema barcodeGallerySchema = JetDataSchema(
  name: 'Symbologies',
  fields: const <FieldDef>[],
);

/// Builds the elements for cell [i] (its [_GalleryEntry]) at its grid slot: a
/// light border tile, the symbology name, and the barcode with its sample value
/// printed underneath.
List<ReportElement> _cellElements(int i, _GalleryEntry entry) {
  final int col = i % _columns;
  final int row = i ~/ _columns;
  final double x = col * (_cellWidth + _columnSpacing);
  final double y = _gridTop + row * (_cellHeight + _rowSpacing);
  return <ReportElement>[
    ShapeElement(
      id: 'border-$i',
      bounds: JetRect(x: x, y: y, width: _cellWidth, height: _cellHeight),
      kind: ShapeKind.rectangle,
      style: const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
    ),
    TextElement(
      id: 'label-$i',
      bounds: JetRect(
        x: x + _pad,
        y: y + 6,
        width: _cellWidth - _pad * 2,
        height: 16,
      ),
      text: entry.label,
      style: const JetTextStyle(fontSize: 11, weight: JetFontWeight.bold),
    ),
    BarcodeElement(
      id: 'code-$i',
      bounds: JetRect(
        x: x + _pad,
        y: y + 26,
        width: _cellWidth - _pad * 2,
        height: _cellHeight - 26 - _pad,
      ),
      symbology: entry.symbology,
      data: entry.value,
    ),
  ];
}

/// The static symbology-gallery report: a page heading plus a single detail
/// band carrying the 2 × 6 grid of [_gallery] cells, drawn once.
ReportDefinition barcodeGalleryDefinition() => ReportDefinition(
      name: 'Barcode symbology gallery',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'gallery',
              type: BandType.detail,
              height: 780,
              elements: <ReportElement>[
                TextElement(
                  id: 'heading',
                  bounds: const JetRect(x: 0, y: 0, width: 538, height: 24),
                  text: 'Newly supported barcode symbologies',
                  style: const JetTextStyle(
                      fontSize: 15, weight: JetFontWeight.bold),
                ),
                for (int i = 0; i < _gallery.length; i++)
                  ..._cellElements(i, _gallery[i]),
              ],
            )),
          ],
        ),
      ),
    );
