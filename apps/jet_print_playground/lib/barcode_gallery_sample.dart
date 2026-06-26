/// A **barcode-symbology gallery**: a single A4 page that draws every newly
/// wired 1D symbology, then a section of QR codes showing the same QR
/// symbology carrying many different payloads (the kinds a restaurant or shop
/// puts on table tents and signage — menu URL, Wi-Fi join, call, reserve, map,
/// contact card, review, promo, chat).
///
/// The symbology is fixed per [BarcodeElement] — it is a compile-time enum, not
/// a bindable field — and a single detail band cannot paginate (it clips), so
/// the gallery is authored as one **static** page: one detail band, rendered
/// once over a single empty row, holding every cell at a fixed position.
///
/// A QR code is payload-agnostic: the *scanner* interprets the conventions
/// (`WIFI:`, `tel:`, `geo:`, `mailto:`, `BEGIN:VCARD`), so the QR section is the
/// one [BarcodeSymbology.qrCode] encoder fed nine different [data] strings.
///
/// Authored entirely through the library's public API, the way a consumer
/// would. Field/label text is illustrative sample data, intentionally not
/// localized.
library;

import 'package:jet_print/jet_print.dart';

/// One 1D gallery cell: the symbology to draw, its display [label], and a
/// sample [value] valid for that symbology (so the code actually encodes).
typedef _OneDEntry = ({BarcodeSymbology symbology, String label, String value});

/// One QR gallery cell: a display [label] for the payload kind and the [value]
/// (payload string) encoded — all drawn with [BarcodeSymbology.qrCode].
typedef _QrEntry = ({String label, String value});

/// The twelve newly wired 1D symbologies, each paired with a valid value.
const List<_OneDEntry> _oneD = <_OneDEntry>[
  (symbology: BarcodeSymbology.code93, label: 'Code 93', value: 'CODE-93'),
  (symbology: BarcodeSymbology.codabar, label: 'Codabar', value: '1234567'),
  (symbology: BarcodeSymbology.itf, label: 'Interleaved 2 of 5', value: '1234'),
  (
    symbology: BarcodeSymbology.gs128,
    label: 'GS1-128',
    value: '(01)00012345678905'
  ),
  (symbology: BarcodeSymbology.upcE, label: 'UPC-E', value: '01234565'),
  (symbology: BarcodeSymbology.ean2, label: 'EAN-2', value: '12'),
  (symbology: BarcodeSymbology.ean5, label: 'EAN-5', value: '12345'),
  (symbology: BarcodeSymbology.postnet, label: 'POSTNET', value: '55555'),
  (symbology: BarcodeSymbology.itf16, label: 'ITF-16', value: '123456789012345'),
  (symbology: BarcodeSymbology.isbn, label: 'ISBN', value: '9780306406157'),
  (symbology: BarcodeSymbology.telepen, label: 'Telepen', value: 'ABC123'),
  (symbology: BarcodeSymbology.rm4scc, label: 'RM4SCC', value: 'LE28HE'),
];

/// Nine QR payloads — all [BarcodeSymbology.qrCode], differing only in their
/// data. Each uses a well-known scan convention so a phone camera acts on it.
const List<_QrEntry> _qr = <_QrEntry>[
  (label: 'Menu (URL)', value: 'https://bistro.example/menu'),
  (label: 'Wi-Fi join', value: 'WIFI:T:WPA;S:Bistro Guest;P:welcome123;;'),
  (label: 'Call (tel:)', value: 'tel:+902125550123'),
  (label: 'Reserve (email)', value: 'mailto:book@bistro.example'),
  (label: 'Map (geo:)', value: 'geo:41.0082,28.9784'),
  (
    label: 'Contact (vCard)',
    value: 'BEGIN:VCARD\nVERSION:3.0\nFN:Bistro\n'
        'TEL:+902125550123\nURL:https://bistro.example\nEND:VCARD'
  ),
  (label: 'Review (URL)', value: 'https://g.page/r/bistro/review'),
  (label: 'Promo (text)', value: 'Happy hour 17-19h: 20% off all mains'),
  (label: 'Chat (WhatsApp)', value: 'https://wa.me/902125550123'),
];

// --- Grid geometry (absolute; A4 portrait content area ≈ 538 × 785 pt) --------

/// Cells per row for both sections.
const int _columns = 3;

/// Horizontal gutter between cells.
const double _gap = 14;

/// Drawn width of one cell: three across the content width with two gutters.
const double _cellWidth = (538 - _gap * 2) / _columns; // 170

/// Inner horizontal padding inside a 1D cell.
const double _pad = 8;

/// Vertical stride between 1D cell rows (label + barcode + gap).
const double _oneDStride = 86;

/// Vertical stride between QR cell rows (label + square module grid + gap).
const double _qrStride = 118;

/// Side length of a QR module grid (square, centred in its cell).
const double _qrSize = 96;

/// Top of the first 1D cell row.
const double _oneDTop = 16;

/// Top of the QR section heading (below the four 1D rows).
const double _qrHeadingTop = 362;

/// Top of the first QR cell row.
const double _qrTop = 382;

/// The gallery needs no real fields — every value is a literal — so the schema
/// is empty. A single empty row drives the one render of the detail band.
final JetDataSchema barcodeGallerySchema = JetDataSchema(
  name: 'Symbologies',
  fields: const <FieldDef>[],
);

/// X coordinate of column [col].
double _colX(int col) => col * (_cellWidth + _gap);

/// Builds one 1D cell ([entry]) at grid slot [i]: a light border, the symbology
/// name, and the barcode with its sample value printed underneath (HRI).
List<ReportElement> _oneDCell(int i, _OneDEntry entry) {
  final double x = _colX(i % _columns);
  final double y = _oneDTop + (i ~/ _columns) * _oneDStride;
  return <ReportElement>[
    ShapeElement(
      id: 'b1-$i',
      bounds: JetRect(x: x, y: y, width: _cellWidth, height: 82),
      kind: ShapeKind.rectangle,
      style: const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
    ),
    TextElement(
      id: 'l1-$i',
      bounds: JetRect(x: x + _pad, y: y + 4, width: _cellWidth - _pad * 2, height: 14),
      text: entry.label,
      style: const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold),
    ),
    BarcodeElement(
      id: 'c1-$i',
      bounds: JetRect(
          x: x + _pad, y: y + 20, width: _cellWidth - _pad * 2, height: 60),
      symbology: entry.symbology,
      data: entry.value,
    ),
  ];
}

/// Builds one QR cell ([entry]) at grid slot [i]: a light border, the payload
/// kind, and a centred QR module grid encoding the payload.
List<ReportElement> _qrCell(int i, _QrEntry entry) {
  final double x = _colX(i % _columns);
  final double y = _qrTop + (i ~/ _columns) * _qrStride;
  return <ReportElement>[
    ShapeElement(
      id: 'bq-$i',
      bounds: JetRect(x: x, y: y, width: _cellWidth, height: 112),
      kind: ShapeKind.rectangle,
      style: const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
    ),
    TextElement(
      id: 'lq-$i',
      bounds: JetRect(x: x + _pad, y: y + 4, width: _cellWidth - _pad * 2, height: 14),
      text: entry.label,
      style: const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold),
    ),
    BarcodeElement(
      id: 'cq-$i',
      // Centred square module grid; QR ignores showText (no HRI for 2D).
      bounds: JetRect(
          x: x + (_cellWidth - _qrSize) / 2,
          y: y + 16,
          width: _qrSize,
          height: _qrSize),
      symbology: BarcodeSymbology.qrCode,
      data: entry.value,
      // Q error-correction: survives print smudges and leaves room for a future
      // centre logo — the level a real table-tent QR menu would use.
      eccLevel: QrErrorCorrectionLevel.q,
    ),
  ];
}

/// The static symbology-gallery report: a page heading, the 1D symbology grid,
/// then a QR-payloads grid — all in a single detail band drawn once.
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
              height: 738,
              elements: <ReportElement>[
                TextElement(
                  id: 'sub1',
                  bounds: const JetRect(x: 0, y: 0, width: 538, height: 12),
                  text: '1D symbologies',
                  style: const JetTextStyle(
                      fontSize: 10, color: JetColor(0xFF666666)),
                ),
                for (int i = 0; i < _oneD.length; i++) ..._oneDCell(i, _oneD[i]),
                TextElement(
                  id: 'sub2',
                  bounds: JetRect(
                      x: 0, y: _qrHeadingTop, width: 538, height: 12),
                  text: 'QR codes — one symbology, many payloads',
                  style: const JetTextStyle(
                      fontSize: 10, color: JetColor(0xFF666666)),
                ),
                for (int i = 0; i < _qr.length; i++) ..._qrCell(i, _qr[i]),
              ],
            )),
          ],
        ),
      ),
    );
