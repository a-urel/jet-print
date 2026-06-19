/// The playground's restaurant-menu sample — a category-grouped list of dishes,
/// each with a data-bound food picture — authored entirely through the library's
/// public API (`package:jet_print/jet_print.dart`).
///
/// It is the first sample to use the engine's `ImageElement`, demonstrating both
/// no-I/O image paths: per-row photos via `FieldImageSource('photo')` (the data
/// carries base64 bytes the fill resolver decodes), and a fixed page-header logo
/// via an embedded `BytesImageSource`. Photos are synthesized in-code as BMP
/// swatches (see `menu_photo.dart`) — abstract gradients, but proof that
/// distinct per-row images bind and paint.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

import 'menu_photo.dart';

/// The menu data structure: a flat dish row. `photo` holds base64 image bytes
/// (declared `string`, since there is no image/bytes field type); the fill
/// resolver turns it into image bytes. Attach it via `dataSchema:`.
const JetDataSchema menuSchema = JetDataSchema(
  name: 'MenuItem',
  fields: <FieldDef>[
    FieldDef('category', type: JetFieldType.string),
    FieldDef('name', type: JetFieldType.string),
    FieldDef('description', type: JetFieldType.string),
    FieldDef('price', type: JetFieldType.double),
    FieldDef('photo', type: JetFieldType.string),
  ],
);

/// A muted grey used for captions and secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// A warm rule color under category headings.
const JetColor _rule = JetColor(0xFFBFA15A);

const String _money = '#,##0.00';

/// The brand-mark bytes embedded in the page header (a small generated swatch
/// standing in for a real logo). Computed once at first use.
final BytesImageSource _logo = BytesImageSource(
  gradientBmp(width: 44, height: 44, topRgb: 0xC9762B, bottomRgb: 0x7A3B12),
);

/// The restaurant-menu report authored in the reified band model (spec 024).
/// Non-const because it embeds generated logo bytes.
ReportDefinition menuSampleDefinition() => ReportDefinition(
      name: 'Menu',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 56,
          elements: <ReportElement>[
            ImageElement(
              id: 'brandLogo',
              bounds: const JetRect(x: 0, y: 4, width: 44, height: 44),
              source: _logo,
              fit: JetBoxFit.contain,
            ),
            const TextElement(
              id: 'brandName',
              bounds: JetRect(x: 56, y: 6, width: 420, height: 24),
              text: 'The Copper Kettle',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
            const TextElement(
              id: 'brandTag',
              bounds: JetRect(x: 56, y: 32, width: 420, height: 16),
              text: 'Seasonal kitchen · est. 2014',
              style: JetTextStyle(fontSize: 10, color: _grey),
            ),
            const ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 53, width: 538, height: 1),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: const <ReportElement>[
            TextElement(
              id: 'footerNote',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 14),
              text: 'Prices in USD',
              style: JetTextStyle(fontSize: 8, color: _grey),
              expression:
                  r'"Prices in USD  ·  Dishes may contain allergens  ·  Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'category',
              name: 'category',
              key: r'$F{category}',
              header: Band(
                id: 'catHeader',
                type: BandType.groupHeader,
                height: 28,
                elements: const <ReportElement>[
                  TextElement(
                    id: 'catName',
                    bounds: JetRect(x: 0, y: 4, width: 538, height: 18),
                    text: 'category',
                    style: JetTextStyle(
                        fontSize: 13, weight: JetFontWeight.bold),
                    expression: r'$F{category}',
                  ),
                  ShapeElement(
                    id: 'catRule',
                    bounds: JetRect(x: 0, y: 24, width: 538, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _rule),
                  ),
                ],
              ),
            ),
          ],
          children: const <ScopeNode>[
            BandNode(Band(
              id: 'item',
              type: BandType.detail,
              height: 64,
              elements: <ReportElement>[
                // Per-row food picture: resolved from the row's base64 `photo`.
                ImageElement(
                  id: 'itemPhoto',
                  bounds: JetRect(x: 0, y: 6, width: 52, height: 52),
                  source: FieldImageSource('photo'),
                  fit: JetBoxFit.cover,
                ),
                TextElement(
                  id: 'itemName',
                  bounds: JetRect(x: 64, y: 6, width: 380, height: 18),
                  text: 'name',
                  style: JetTextStyle(
                      fontSize: 12, weight: JetFontWeight.bold),
                  expression: r'$F{name}',
                ),
                TextElement(
                  id: 'itemDesc',
                  bounds: JetRect(x: 64, y: 26, width: 380, height: 28),
                  text: 'description',
                  style: JetTextStyle(fontSize: 9, color: _grey),
                  expression: r'$F{description}',
                ),
                TextElement(
                  id: 'itemPrice',
                  bounds: JetRect(x: 448, y: 8, width: 90, height: 18),
                  text: 'price',
                  style: JetTextStyle(
                      fontSize: 12,
                      align: JetTextAlign.right,
                      weight: JetFontWeight.bold),
                  expression: r'$F{price}',
                  format: _money,
                ),
              ],
            )),
          ],
        ),
      ),
    );
