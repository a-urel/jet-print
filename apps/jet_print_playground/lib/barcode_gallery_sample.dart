/// A **barcode-symbology gallery**: a single A4 page that draws every newly
/// wired 1D symbology, a row of exotic 2D matrix codes (Aztec, Data Matrix,
/// PDF417), then a section of QR codes showing the same QR symbology carrying
/// many different payloads (the kinds a restaurant or shop puts on table tents
/// and signage — menu URL, Wi-Fi join, call, reserve, map, contact, review,
/// promo, chat).
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

/// One 2D matrix gallery cell: the symbology, a display [label], and the
/// encoded [value].
typedef _TwoDEntry = ({BarcodeSymbology symbology, String label, String value});

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

/// The three exotic 2D matrix symbologies (all supported since spec 036): two
/// square matrices and one stacked-linear PDF417.
const List<_TwoDEntry> _twoD = <_TwoDEntry>[
  (
    symbology: BarcodeSymbology.aztec,
    label: 'Aztec',
    value: 'Aztec 2D — jet_print'
  ),
  (
    symbology: BarcodeSymbology.dataMatrix,
    label: 'Data Matrix',
    value: 'DataMatrix ECC200'
  ),
  (
    symbology: BarcodeSymbology.pdf417,
    label: 'PDF417',
    value: 'PDF417 stacked linear 2D'
  ),
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

/// Cells per row for every section.
const int _columns = 3;

/// Horizontal gutter between cells.
const double _gap = 14;

/// Drawn width of one cell: three across the content width with two gutters.
const double _cellWidth = (538 - _gap * 2) / _columns; // 170

/// Inner padding inside a cell.
const double _pad = 8;

/// Vertical stride between 1D cell rows (label + barcode + gap).
const double _oneDStride = 78;

/// Vertical stride between QR cell rows (label + square module grid + gap).
const double _qrStride = 100;

/// Side length of a QR module grid (square, centred in its cell).
const double _qrSize = 76;

/// Side length of a square 2D matrix (Aztec / Data Matrix), centred.
const double _matrixSize = 70;

/// Top of the first 1D cell row.
const double _oneDTop = 14;

/// Top of the 2D-matrix section heading (below the four 1D rows).
const double _twoDHeadingTop = 326;

/// Top of the single 2D-matrix cell row.
const double _twoDTop = 344;

/// Top of the QR section heading (below the 2D row).
const double _qrHeadingTop = 446;

/// Top of the first QR cell row.
const double _qrTop = 464;

/// The gallery needs no real fields — every value is a literal — so the schema
/// is empty. A single empty row drives the one render of the detail band.
final JetDataSchema barcodeGallerySchema = JetDataSchema(
  name: 'Symbologies',
  fields: const <FieldDef>[],
);

/// X coordinate of column [col].
double _colX(int col) => col * (_cellWidth + _gap);

/// A light border tile for a cell at ([x], [y]) of the given [height].
ShapeElement _border(String id, double x, double y, double height) =>
    ShapeElement(
      id: id,
      bounds: JetRect(x: x, y: y, width: _cellWidth, height: height),
      kind: ShapeKind.rectangle,
      style: const JetBoxStyle(stroke: JetColor(0xFFCCCCCC), strokeWidth: 0.75),
    );

/// A bold cell caption at the top of the cell at ([x], [y]).
TextElement _caption(String id, double x, double y, String text) => TextElement(
      id: id,
      bounds:
          JetRect(x: x + _pad, y: y + 4, width: _cellWidth - _pad * 2, height: 14),
      text: text,
      style: const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold),
    );

/// A grey section heading spanning the content width at [top].
TextElement _heading(String id, double top, String text) => TextElement(
      id: id,
      bounds: JetRect(x: 0, y: top, width: 538, height: 12),
      text: text,
      style: const JetTextStyle(fontSize: 10, color: JetColor(0xFF666666)),
    );

/// Builds one 1D cell ([entry]) at grid slot [i]: border, symbology name, and
/// the barcode with its sample value printed underneath (HRI).
List<ReportElement> _oneDCell(int i, _OneDEntry entry) {
  final double x = _colX(i % _columns);
  final double y = _oneDTop + (i ~/ _columns) * _oneDStride;
  return <ReportElement>[
    _border('b1-$i', x, y, 72),
    _caption('l1-$i', x, y, entry.label),
    BarcodeElement(
      id: 'c1-$i',
      bounds: JetRect(
          x: x + _pad, y: y + 20, width: _cellWidth - _pad * 2, height: 50),
      symbology: entry.symbology,
      data: entry.value,
    ),
  ];
}

/// Builds one 2D-matrix cell ([entry]) at grid slot [i]: border, name, and the
/// matrix — a centred square for Aztec/Data Matrix, a wide stacked block for
/// PDF417 (which is ≈3:1, not square).
List<ReportElement> _twoDCell(int i, _TwoDEntry entry) {
  final double x = _colX(i % _columns);
  const double y = _twoDTop;
  final bool wide = entry.symbology == BarcodeSymbology.pdf417;
  final JetRect codeBounds = wide
      ? JetRect(
          x: x + _pad, y: y + 32, width: _cellWidth - _pad * 2, height: 50)
      : JetRect(
          x: x + (_cellWidth - _matrixSize) / 2,
          y: y + 18,
          width: _matrixSize,
          height: _matrixSize);
  return <ReportElement>[
    _border('b2-$i', x, y, 96),
    _caption('l2-$i', x, y, entry.label),
    BarcodeElement(
      id: 'c2-$i',
      bounds: codeBounds,
      symbology: entry.symbology,
      data: entry.value,
    ),
  ];
}

/// Builds one QR cell ([entry]) at grid slot [i]: border, payload kind, and a
/// centred QR module grid encoding the payload.
List<ReportElement> _qrCell(int i, _QrEntry entry) {
  final double x = _colX(i % _columns);
  final double y = _qrTop + (i ~/ _columns) * _qrStride;
  return <ReportElement>[
    _border('bq-$i', x, y, 94),
    _caption('lq-$i', x, y, entry.label),
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

/// The static symbology-gallery report: the 1D symbology grid, a row of exotic
/// 2D matrix codes, then a QR-payloads grid — all in a single detail band.
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
              height: 766,
              elements: <ReportElement>[
                _heading('sub1', 0, '1D symbologies'),
                for (int i = 0; i < _oneD.length; i++) ..._oneDCell(i, _oneD[i]),
                _heading('sub2', _twoDHeadingTop, '2D matrix codes'),
                for (int i = 0; i < _twoD.length; i++) ..._twoDCell(i, _twoD[i]),
                _heading('sub3', _qrHeadingTop,
                    'QR codes — one symbology, many payloads'),
                for (int i = 0; i < _qr.length; i++) ..._qrCell(i, _qr[i]),
              ],
            )),
          ],
        ),
      ),
    );
