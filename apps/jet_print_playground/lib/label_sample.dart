/// The playground's label sample: a **3-column address-label sheet** authored
/// entirely through the library's public API (`package:jet_print/jet_print.dart`),
/// the way an external consumer would.
///
/// The engine flows `detail` bands top-to-bottom only — native multi-column
/// flow (`columnHeader`/`columnFooter`) is reserved but not laid out yet. So a
/// 3-across-then-wrap label sheet is achieved by **reshaping the data**: the
/// flat address list is pre-chunked into rows of three (see
/// `rendered_label_example.dart`), and each row becomes one master record whose
/// fields are prefix-namespaced per cell — `c0*`, `c1*`, `c2*`. The single
/// `detail` band is one label-row tall and lays three column blocks side by
/// side at fixed X offsets; the engine then flows those rows down the page.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// How many label cells sit across one row. Each cell `i` (0-based) is bound to
/// the `c{i}*` fields of the chunked master record.
const int labelColumns = 3;

// --- Page-relative geometry (A4 portrait content area ≈ 538 × 785 pt) ---------

/// Horizontal pitch between cells: content width (≈538) ÷ [labelColumns].
const double _columnPitch = 179;

/// Drawn width of a single label tile (pitch minus the inter-cell gutter).
const double _cellWidth = 170;

/// Height of one label row. Eight rows (8 × 98 = 784) fill the content height,
/// so each A4 page carries 8 × [labelColumns] = 24 labels.
const double _rowHeight = 98;

/// Inner padding from the tile's border to its text.
const double _pad = 10;

/// The address fields each cell carries, in stacking order. Names are
/// per-cell-prefixed at bind time (`c0Name`, `c1Name`, …).
const List<String> _cellFields = <String>['Name', 'Street', 'City', 'Country'];

/// The flat data schema the chunked rows satisfy: [labelColumns] cells, each
/// with the four address fields, prefixed `c{i}{Field}`. Attach via `dataSchema:`.
final JetDataSchema labelSchema = JetDataSchema(
  name: 'Labels',
  fields: <FieldDef>[
    for (int i = 0; i < labelColumns; i++)
      for (final String f in _cellFields)
        FieldDef('c$i$f', type: JetFieldType.string),
  ],
);

/// Builds the elements for one label cell at column [index]: a light border
/// tile plus the four-line address bound to that cell's `c{index}*` fields.
List<ReportElement> _cellElements(int index) {
  final double x = index * _columnPitch;
  final String p = 'c$index'; // field/id prefix for this cell
  return <ReportElement>[
    // The cut-tile border (data-blind; drawn for every cell slot).
    ShapeElement(
      id: '${p}Border',
      bounds: JetRect(x: x, y: 2, width: _cellWidth, height: _rowHeight - 6),
      kind: ShapeKind.rectangle,
      style: const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
    ),
    TextElement(
      id: '${p}Name',
      bounds:
          JetRect(x: x + _pad, y: 12, width: _cellWidth - _pad * 2, height: 18),
      text: '${p}Name',
      style: const JetTextStyle(fontSize: 11, weight: JetFontWeight.bold),
      expression: '\$F{${p}Name}',
    ),
    TextElement(
      id: '${p}Street',
      bounds:
          JetRect(x: x + _pad, y: 32, width: _cellWidth - _pad * 2, height: 16),
      text: '${p}Street',
      expression: '\$F{${p}Street}',
    ),
    TextElement(
      id: '${p}City',
      bounds:
          JetRect(x: x + _pad, y: 50, width: _cellWidth - _pad * 2, height: 16),
      text: '${p}City',
      expression: '\$F{${p}City}',
    ),
    TextElement(
      id: '${p}Country',
      bounds:
          JetRect(x: x + _pad, y: 68, width: _cellWidth - _pad * 2, height: 16),
      text: '${p}Country',
      style: const JetTextStyle(fontSize: 9, color: JetColor(0xFF888888)),
      expression: '\$F{${p}Country}',
    ),
  ];
}

/// The 3-column label-sheet report, authored in the reified band model.
///
/// Furniture-free (labels carry no page header/footer): the body's root
/// [DetailScope] iterates the chunked rows, and its single per-row `detail`
/// band ([_rowHeight] tall) lays [labelColumns] cells side by side. The engine
/// flows the rows down the page, wrapping to the next page after eight.
ReportDefinition labelSampleDefinition() => ReportDefinition(
      name: 'Labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'labelRow',
              type: BandType.detail,
              height: _rowHeight,
              elements: <ReportElement>[
                for (int i = 0; i < labelColumns; i++) ..._cellElements(i),
              ],
            )),
          ],
        ),
      ),
    );
