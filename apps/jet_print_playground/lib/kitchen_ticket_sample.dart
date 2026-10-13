/// The playground's kitchen-ticket sample: one restaurant order printed on an
/// **80 mm thermal roll**, split into **one ticket per station** — kitchen,
/// bar, dessert — each cut to its own length. Authored entirely through the
/// library's public API (`package:jet_print/jet_print.dart`).
///
/// It is the roll-paper feature end to end:
///
/// - the page is `continuous`, so each ticket is as long as its content and
///   `height` is only the shortest a ticket may be;
/// - the station group has `startNewPage`, so each station's items print on
///   a ticket of their own, each repeating the order header;
/// - an item's note prints under it only when the item has one, through an
///   element whose `visible` is an expression.
///
/// Rendered to PNG at the printer's resolution
/// (`JetReportExporter.pageToPng(report, i, scale: 203 / 72)`), each page is
/// the raster an ESC/POS printer takes.
///
/// The rows are illustrative Turkish order data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// 80 mm in PostScript points: the width of the common thermal roll.
const double _rollWidth = 80 / 25.4 * 72;

/// Left/right margins keep text off the print head's unprintable edges; the
/// taller bottom margin leaves room above the cutter.
const JetEdgeInsets _margins =
    JetEdgeInsets(left: 8, top: 8, right: 8, bottom: 16);

const double _contentWidth = _rollWidth - 16;

/// The order data structure: one row per ordered item, each carrying the
/// order's header fields and the station that prepares it. Rows are sorted by
/// station, since a group breaks when its key changes. Attach it via
/// `dataSchema:`.
const JetDataSchema kitchenTicketSchema = JetDataSchema(
  name: 'Order',
  fields: <FieldDef>[
    FieldDef('orderNo',
        type: JetFieldType.integer, description: 'Order number'),
    FieldDef('table', type: JetFieldType.string, description: 'Table'),
    FieldDef('waiter', type: JetFieldType.string, description: 'Waiter'),
    FieldDef('time',
        type: JetFieldType.string, description: 'Order time, HH:mm'),
    FieldDef('station',
        type: JetFieldType.string, description: 'Preparing station'),
    FieldDef('qty', type: JetFieldType.integer, description: 'Quantity'),
    FieldDef('item', type: JetFieldType.string, description: 'Menu item'),
    FieldDef('note',
        type: JetFieldType.string, description: 'Note, empty when none'),
  ],
);

/// The kitchen-ticket definition: an 80 mm continuous roll, grouped by
/// station with a new ticket per station.
ReportDefinition kitchenTicketDefinition() => const ReportDefinition(
      name: 'Kitchen ticket',
      page: PageFormat(
        width: _rollWidth,
        // The shortest a ticket may be: 50 mm.
        height: 50 / 25.4 * 72,
        margins: _margins,
        continuous: true,
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'station',
              name: 'station',
              key: r'$F{station}',
              startNewPage: true,
              header: Band(
                id: 'stationHeader',
                type: BandType.groupHeader,
                height: 72,
                elements: <ReportElement>[
                  TextElement(
                    id: 'stationName',
                    bounds:
                        JetRect(x: 0, y: 0, width: _contentWidth, height: 26),
                    text: '',
                    expression: r'UPPER($F{station})',
                    style: JetTextStyle(
                      fontSize: 20,
                      weight: JetFontWeight.bold,
                      align: JetTextAlign.center,
                    ),
                  ),
                  TextElement(
                    id: 'tableWaiter',
                    bounds:
                        JetRect(x: 0, y: 30, width: _contentWidth, height: 16),
                    text: '',
                    expression: r'"Masa " + $F{table} + " · " + $F{waiter}',
                    style:
                        JetTextStyle(fontSize: 12, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'orderTime',
                    bounds:
                        JetRect(x: 0, y: 48, width: _contentWidth, height: 14),
                    text: '',
                    expression:
                        r'"Sipariş #" + FORMAT($F{orderNo}, "0") + " · " + $F{time}',
                    style: JetTextStyle(fontSize: 10),
                  ),
                  ShapeElement(
                    id: 'headerRule',
                    bounds:
                        JetRect(x: 0, y: 66, width: _contentWidth, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: JetColor.black),
                  ),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
              id: 'item',
              type: BandType.detail,
              height: 34,
              elements: <ReportElement>[
                TextElement(
                  id: 'qtyItem',
                  bounds: JetRect(x: 0, y: 2, width: _contentWidth, height: 16),
                  text: '',
                  expression: r'FORMAT($F{qty}, "0") + " × " + $F{item}',
                  style: JetTextStyle(fontSize: 13, weight: JetFontWeight.bold),
                ),
                // Omitted at fill time when the row has no note. The band keeps
                // its height either way: one scope renders one per-row band, so
                // the note cannot be a band of its own.
                TextElement(
                  id: 'noteText',
                  bounds: JetRect(
                      x: 16, y: 18, width: _contentWidth - 16, height: 14),
                  text: '',
                  expression: r'"Not: " + $F{note}',
                  visible: BoolProperty(expression: r'LENGTH($F{note}) > 0'),
                  style: JetTextStyle(fontSize: 11, italic: true),
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The sample order: table B4's order, sorted by station.
List<Map<String, Object?>> kitchenTicketData() {
  Map<String, Object?> row(String station, int qty, String item,
          [String note = '']) =>
      <String, Object?>{
        'orderNo': 1042,
        'table': 'B4',
        'waiter': 'Ayşe',
        'time': '19:42',
        'station': station,
        'qty': qty,
        'item': item,
        'note': note,
      };
  return <Map<String, Object?>>[
    row('Mutfak', 2, 'Adana kebap', 'acısız'),
    row('Mutfak', 1, 'Lahmacun'),
    row('Mutfak', 1, 'Mercimek çorbası'),
    row('Bar', 2, 'Ayran'),
    row('Bar', 1, 'Türk kahvesi', 'orta şekerli'),
    row('Tatlı', 1, 'Künefe'),
  ];
}
