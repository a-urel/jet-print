/// The playground's **Custom** sample — a price watchlist that shows off the
/// per-element `onPrint` host hook (`RenderOptions.onElementPrint`, spec
/// 2026-06-27). The report itself is plain: one detail row per ticker with a
/// direction marker, symbol, last price, and change. All the *conditional
/// formatting* lives in host Dart code, not in the template:
///
/// * the `changeArrow` cell is a placeholder [ShapeElement]; on a move the hook
///   swaps its [ShapeKind] to a block arrow (up / down) — real geometry, not a
///   font glyph — coloured by direction, and suppresses it (`null`) when flat,
/// * the sibling `changeFlat` cell is a thin grey dash, shown only when flat
///   and suppressed on a move — a second element because each marker needs its
///   own authored height (the hook cannot change measured height),
/// * the `changeValue` cell keeps its filled number but is recolored green for
///   a gain, red for a loss, grey for flat.
///
/// The arrow is a shape, not a ▲/▼ text glyph, on purpose: the bundled fonts
/// have no Geometric-Shapes coverage, so a triangle character renders as tofu.
/// `arrowUp`/`arrowDown` are drawn by the engine as paths and need no font.
///
/// The hook branches on the **raw** field value (`ctx.fields['change']`, a
/// [JetNumber]) and rewrites only presentation — the Jasper-style separation of
/// data and display. Because it returns same-type copies (shape→shape,
/// text→text) it is faithful to the contract: never change the element's type
/// or measured size.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

/// A flat watchlist row: a ticker, its last price, and the day's change.
const JetDataSchema watchlistSchema = JetDataSchema(
  name: 'Watchlist',
  fields: <FieldDef>[
    FieldDef('symbol', type: JetFieldType.string),
    FieldDef('name', type: JetFieldType.string),
    FieldDef('price', type: JetFieldType.double),
    FieldDef('change', type: JetFieldType.double),
  ],
);

/// Muted grey — secondary text, headings, and the flat marker.
const JetColor _grey = JetColor(0xFF888888);

/// A thin rule under the column headings.
const JetColor _rule = JetColor(0xFFB0B0B0);

/// Gain (positive change).
const JetColor _up = JetColor(0xFF1B873F);

/// Loss (negative change).
const JetColor _down = JetColor(0xFFD32F2F);

/// Two-decimal money mask.
const String _money = '#,##0.00';

/// The watchlist report, authored in the reified band model (spec 024). The
/// `changeArrow` cell ships as a neutral grey line placeholder — the
/// [onElementPrint] hook is what turns it into a coloured up/down block arrow
/// at emit time.
ReportDefinition customOnPrintDefinition() => ReportDefinition(
      name: 'Watchlist',
      page: PageFormat.a4Portrait,
      furniture: const PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 44,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 538, height: 18),
              text: 'Watchlist',
              style: JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'subtitle',
              bounds: JetRect(x: 0, y: 18, width: 538, height: 12),
              text: 'Conditional formatting via onElementPrint',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hSymbol',
              bounds: JetRect(x: 22, y: 32, width: 160, height: 12),
              text: 'Symbol',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hName',
              bounds: JetRect(x: 190, y: 32, width: 200, height: 12),
              text: 'Name',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hPrice',
              bounds: JetRect(x: 392, y: 32, width: 70, height: 12),
              text: 'Price',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hChange',
              bounds: JetRect(x: 466, y: 32, width: 72, height: 12),
              text: 'Change',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 42, width: 538, height: 0.75),
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
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'tick',
              type: BandType.detail,
              height: 18,
              elements: <ReportElement>[
                // Two stacked direction markers, one shown per row: the hook
                // turns `changeArrow` into an up/down block arrow on a move and
                // suppresses it when flat, and shows the thin `changeFlat` dash
                // only when flat. Two elements because each needs its own
                // authored HEIGHT — the hook can change x/y/width and style but
                // not measured height (the emit-time fixed-size contract).
                ShapeElement(
                  id: 'changeArrow',
                  bounds: JetRect(x: 4, y: 4, width: 10, height: 10),
                  kind: ShapeKind.line,
                  style: JetBoxStyle(stroke: _grey),
                ),
                ShapeElement(
                  id: 'changeFlat',
                  bounds: JetRect(x: 4, y: 8, width: 10, height: 2),
                  kind: ShapeKind.rectangle,
                  style: JetBoxStyle(fill: _grey),
                ),
                TextElement(
                  id: 'symbol',
                  bounds: JetRect(x: 22, y: 2, width: 160, height: 14),
                  text: 'symbol',
                  style: JetTextStyle(weight: JetFontWeight.bold),
                  expression: r'$F{symbol}',
                ),
                TextElement(
                  id: 'name',
                  bounds: JetRect(x: 190, y: 2, width: 200, height: 14),
                  text: 'name',
                  style: JetTextStyle(fontSize: 9, color: _grey),
                  expression: r'$F{name}',
                ),
                TextElement(
                  id: 'price',
                  bounds: JetRect(x: 392, y: 2, width: 70, height: 14),
                  text: 'price',
                  style: JetTextStyle(align: JetTextAlign.right),
                  expression: r'$F{price}',
                  format: _money,
                ),
                // Filled with the number; the hook recolours it per row.
                TextElement(
                  id: 'changeValue',
                  bounds: JetRect(x: 466, y: 2, width: 72, height: 14),
                  text: 'change',
                  style: JetTextStyle(align: JetTextAlign.right),
                  expression: r'$F{change}',
                  format: _money,
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The demo data source: eight tickers with mixed gains, losses, and a flat.
JetDataSource watchlistDataSource() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'symbol': 'ACME',
        'name': 'Acme Industries',
        'price': 142.18,
        'change': 3.42,
      },
      <String, Object?>{
        'symbol': 'GLBX',
        'name': 'Globex Corp',
        'price': 88.05,
        'change': -1.27,
      },
      <String, Object?>{
        'symbol': 'INIT',
        'name': 'Initech',
        'price': 26.74,
        'change': 0.0,
      },
      <String, Object?>{
        'symbol': 'UMBR',
        'name': 'Umbrella Co',
        'price': 311.90,
        'change': 12.55,
      },
      <String, Object?>{
        'symbol': 'STRK',
        'name': 'Stark Holdings',
        'price': 204.33,
        'change': -8.10,
      },
      <String, Object?>{
        'symbol': 'WAYN',
        'name': 'Wayne Enterprises',
        'price': 176.42,
        'change': 0.64,
      },
      <String, Object?>{
        'symbol': 'TYRL',
        'name': 'Tyrell Corp',
        'price': 59.18,
        'change': 0.0,
      },
      <String, Object?>{
        'symbol': 'OSCN',
        'name': 'Oscorp',
        'price': 97.86,
        'change': 5.21,
      },
    ]);

/// The per-element host hook: conditional formatting driven by the raw `change`
/// field. Returns same-type copies — shape→shape, text→text — so it never
/// changes an element's runtime type, and uses `null` to suppress the marker
/// that does not apply this row.
ReportElement? _formatByChange(ReportElement el, ElementPrintContext ctx) {
  final JetValue? raw = ctx.fields['change'];
  final double change = raw is JetNumber ? raw.value : 0.0;
  final bool flat = change == 0;
  final JetColor color = change > 0
      ? _up
      : change < 0
          ? _down
          : _grey;

  // The up/down arrow: a coloured block arrow on a move, hidden when flat.
  if (el is ShapeElement && el.id == 'changeArrow') {
    if (change > 0) {
      return el.copyWith(
          kind: ShapeKind.arrowUp, style: JetBoxStyle(fill: _up));
    }
    if (change < 0) {
      return el.copyWith(
          kind: ShapeKind.arrowDown, style: JetBoxStyle(fill: _down));
    }
    return null; // flat: the thin dash element shows instead.
  }
  // The thin dash: shown only when flat (suppressed on a move).
  if (el is ShapeElement && el.id == 'changeFlat') {
    return flat ? el : null;
  }
  // The change value: keep the filled number, recolour it.
  if (el is TextElement && el.id == 'changeValue') {
    return el.copyWith(style: el.style.copyWith(color: color));
  }
  return el;
}

/// The flat set of every schema field name (for schema-aware render).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };

/// Renders the watchlist with [_formatByChange] wired into [RenderOptions].
RenderedReport renderCustomOnPrintDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? customOnPrintDefinition(),
      source ?? watchlistDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(watchlistSchema.fields),
        fonts: fonts,
        onElementPrint: _formatByChange,
      ),
    );
