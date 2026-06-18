/// The playground's label sample: a **3-column address-label sheet** authored
/// entirely through the library's public API (`package:jet_print/jet_print.dart`),
/// the way an external consumer would.
///
/// Built on the engine's **native multi-column label support** (spec 034): the
/// detail band carries a [ColumnLayout], so a single label cell is authored
/// once — in cell-local coordinates — and the engine repeats it across the grid
/// in horizontal print order (left-to-right, wrapping down, then to the next
/// page). The data is a **flat** address list (one address per master row); the
/// grid placement does the columns. (Before spec 034 this sheet faked columns
/// by pre-chunking the data into `c0*`/`c1*`/`c2*` rows and hand-placing three
/// blocks in one band — no longer needed.)
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// How many label cells sit across one row — the grid's [ColumnLayout.columnCount].
const int labelColumns = 3;

// --- Cell geometry (cell-local; the grid offsets each repeat) -----------------
//
// A4 portrait content area ≈ 538 × 785 pt. The grid is [labelColumns] cells of
// [_cellWidth] separated by [_columnSpacing]: 3 × 170 + 2 × 9 = 528 ≤ 538, so it
// fits the body. Eight [_rowHeight]-tall rows (8 × 98 = 784 ≤ 785) fill the page
// height, so each A4 page carries 8 × [labelColumns] = 24 labels.

/// Drawn width of a single label tile — the grid's [ColumnLayout.columnWidth].
const double _cellWidth = 170;

/// Horizontal gutter between cells — the grid's [ColumnLayout.columnSpacing].
const double _columnSpacing = 9;

/// Height of one label row (one detail-band instance).
const double _rowHeight = 98;

/// Vertical gap between label rows — the grid's [ColumnLayout.rowSpacing].
const double _rowSpacing = 0;

/// Inner padding from the tile's border to its text.
const double _pad = 10;

/// The flat data schema one address record satisfies — the four address fields,
/// one record per label cell. Attach via `dataSchema:`.
final JetDataSchema labelSchema = JetDataSchema(
  name: 'Labels',
  fields: <FieldDef>[
    FieldDef('name', type: JetFieldType.string),
    FieldDef('street', type: JetFieldType.string),
    FieldDef('city', type: JetFieldType.string),
    FieldDef('country', type: JetFieldType.string),
  ],
);

/// Builds the elements for **one** label cell, in cell-local coordinates (the
/// grid repeats this cell across the columns): a light border tile plus the
/// four-line address bound to the flat `name`/`street`/`city`/`country` fields.
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
        id: 'name',
        bounds:
            JetRect(x: _pad, y: 12, width: _cellWidth - _pad * 2, height: 18),
        text: 'Name',
        style: const JetTextStyle(fontSize: 11, weight: JetFontWeight.bold),
        expression: '\$F{name}',
      ),
      TextElement(
        id: 'street',
        bounds:
            JetRect(x: _pad, y: 32, width: _cellWidth - _pad * 2, height: 16),
        text: 'Street',
        expression: '\$F{street}',
      ),
      TextElement(
        id: 'city',
        bounds:
            JetRect(x: _pad, y: 50, width: _cellWidth - _pad * 2, height: 16),
        text: 'City',
        expression: '\$F{city}',
      ),
      TextElement(
        id: 'country',
        bounds:
            JetRect(x: _pad, y: 68, width: _cellWidth - _pad * 2, height: 16),
        text: 'Country',
        style: const JetTextStyle(fontSize: 9, color: JetColor(0xFF888888)),
        expression: '\$F{country}',
      ),
    ];

/// The 3-column label-sheet report, authored in the reified band model with a
/// native [ColumnLayout].
///
/// Furniture-free (labels carry no page header/footer): the body's root
/// [DetailScope] iterates the flat address rows, and its single per-row `detail`
/// band — one label cell, [_rowHeight] tall — carries the [ColumnLayout] that
/// repeats it across [labelColumns] columns. The engine places the cells in
/// horizontal order and wraps down the page, then to the next page.
ReportDefinition labelSampleDefinition() => ReportDefinition(
      name: 'Labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'labelCell',
              type: BandType.detail,
              height: _rowHeight,
              columnLayout: const ColumnLayout(
                columnCount: labelColumns,
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
