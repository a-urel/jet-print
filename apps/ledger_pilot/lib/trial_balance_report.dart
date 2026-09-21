/// The pilot's report: a Turkish trial balance ("mizan") over the TDHP chart
/// of accounts, authored entirely through `package:jet_print/jet_print.dart`.
///
/// Structure, outermost first:
///
/// * page furniture — a running head that repeats the company, the period and
///   the **column captions** on every page, and a footer carrying
///   "Sayfa N / M";
/// * a title band printed once;
/// * a class group (`1`, `2`, `3`, …) with a header and a subtotal footer;
/// * a main-account group (`100`, `102`, …) with a header and a subtotal
///   footer, kept together on one page where it fits;
/// * one detail band per posting account;
/// * a summary band carrying the grand total and the balance check.
///
/// Both group keys are derived from the account code with `SUBSTRING`, which
/// is what makes the TDHP prefix hierarchy a grouping the engine can express
/// without the host inventing a sort key for it.
///
/// Every money figure in the report is computed by the engine. The rows carry
/// only `acilis`, `borc` and `alacak`; the closing balance is
/// `acilis + borc - alacak` per row and `SUM(acilis + borc - alacak)` per
/// subtotal, and no total anywhere is precomputed in Dart.
///
/// User-visible strings are Turkish because the report is Turkish. Code and
/// comments are not.
library;

import 'package:jet_print/jet_print.dart';

/// The content width of an A4 portrait page under [PageFormat.a4Portrait]'s
/// own 28.35pt margins: 595.28 - 2 x 28.35 = 538.58, rounded down.
const double _contentWidth = 538;

// The column grid, in points from the left edge of the content box. Four money
// columns of 72pt hold a thirteen-character figure ("24.919.123,25") at 8pt
// with room to spare, which the grand total needs and the detail rows do not.
const double _codeX = 0;
const double _codeW = 54;
const double _nameX = 58;
const double _nameW = 178;
const double _openingX = 240;
const double _debitX = 314;
const double _creditX = 388;
const double _closingX = 462;
const double _moneyW = 72;

/// The width of a total label spanning the code and name columns.
const double _labelW = 236;

/// The ICU pattern every money cell uses.
///
/// It is locale-interpreted: under `RenderOptions.locale` of `tr` the grouping
/// separator is `.` and the decimal separator `,`, which is what a Turkish
/// mizan wants. The pattern alone does not say that — see the pilot's README.
const String _money = '#,##0.00';

/// Muted grey for captions, rules and secondary text.
const JetColor _grey = JetColor(0xFF7A7A7A);

/// A pale fill behind a class heading.
const JetColor _classFill = JetColor(0xFFEDEFF4);

// --- The four money columns, as expressions ---------------------------------
//
// Signed convention: a debit balance is positive, a credit balance negative.
// That is what lets one arithmetic expression serve every account class, and
// it is why the opening and closing grand totals read 0,00.

/// A row's closing balance.
const String _rowClosing = r'$F{acilis} + $F{borc} - $F{alacak}';

/// A subtotal's opening balance.
const String _sumOpening = r'SUM($F{acilis})';

/// A subtotal's period debit.
const String _sumDebit = r'SUM($F{borc})';

/// A subtotal's period credit.
const String _sumCredit = r'SUM($F{alacak})';

/// A subtotal's closing balance.
///
/// Written as one aggregate over a compound operand rather than as
/// `SUM($F{acilis}) + SUM($F{borc}) - SUM($F{alacak})`. The two are equal, and
/// the engine folds either: the synthesizer lifts an aggregate wherever it
/// appears, including inside surrounding arithmetic. The single-aggregate form
/// is used because `validate()` treats the other one's operands as
/// record-blind field references in the summary band — see [_difference].
const String _sumClosing = r'SUM($F{acilis} + $F{borc} - $F{alacak})';

/// The accountant's check: total debits less total credits, which must be
/// zero for the mizan to hold.
///
/// Deliberately written the natural way, with two aggregates inside one
/// subtraction. The engine folds it correctly, but `validate()` reports the
/// summary band as referencing the fields `borc` and `alacak` "which have no
/// data row" — a false positive, because they are aggregate operands, not a
/// record-blind binding. The check only exempts an expression whose *root* is
/// an aggregate call. Kept as written so the pilot carries the evidence.
const String _difference = r'SUM($F{borc}) - SUM($F{alacak})';

/// The class group's key: the first digit of the account code.
const String _classKey = r'SUBSTRING($F{hesapKodu}, 0, 1)';

/// The main-account group's key: the first three digits of the account code.
const String _mainAccountKey = r'SUBSTRING($F{hesapKodu}, 0, 3)';

/// Builds the trial-balance definition.
///
/// A function rather than a top-level constant so the pilot reads the way a
/// host would write it, and so the layout constants above stay the only
/// duplicated numbers.
ReportDefinition trialBalanceDefinition() => const ReportDefinition(
      name: 'Mizan',
      page: PageFormat.a4Portrait,
      parameters: <ReportParameter>[
        ReportParameter(
          name: 'firmaAdi',
          type: JetFieldType.string,
          defaultValue: 'Anadolu Ticaret A.Ş.',
        ),
        ReportParameter(
          name: 'donem',
          type: JetFieldType.string,
          defaultValue: '01.01.2026 - 31.12.2026',
        ),
      ],
      furniture: PageFurniture(
        // The running head carries the column captions because it is the only
        // furniture slot the layouter lays out. PageFurniture.columnHeader
        // exists and takes a Band, but is reserved: it draws nothing and
        // records an info diagnostic.
        pageHeader: Band(
          id: 'ph',
          type: BandType.pageHeader,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 'ph/firma',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 11),
              text: 'firmaAdi',
              style: JetTextStyle(
                fontSize: 8,
                color: _grey,
                weight: JetFontWeight.bold,
              ),
              expression: r'$P{firmaAdi}',
            ),
            TextElement(
              id: 'ph/donem',
              bounds: JetRect(x: 320, y: 0, width: 218, height: 11),
              text: 'donem',
              style: JetTextStyle(
                fontSize: 8,
                color: _grey,
                align: JetTextAlign.right,
              ),
              expression: r'"Dönem: " + $P{donem}',
            ),
            ShapeElement(
              id: 'ph/ruleTop',
              bounds: JetRect(x: 0, y: 14, width: _contentWidth, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _grey),
            ),
            TextElement(
              id: 'ph/capCode',
              bounds: JetRect(x: _codeX, y: 23, width: _codeW, height: 10),
              text: 'Hesap Kodu',
              style: JetTextStyle(fontSize: 7.5, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'ph/capName',
              bounds: JetRect(x: _nameX, y: 23, width: _nameW, height: 10),
              text: 'Hesap Adı',
              style: JetTextStyle(fontSize: 7.5, weight: JetFontWeight.bold),
            ),
            // Two-line captions: one line of "Açılış Bakiyesi" would wrap
            // inside a 72pt column, and a wrapped caption grows the band.
            TextElement(
              id: 'ph/capOpening1',
              bounds: JetRect(x: _openingX, y: 18, width: _moneyW, height: 10),
              text: 'Açılış',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capOpening2',
              bounds: JetRect(x: _openingX, y: 28, width: _moneyW, height: 10),
              text: 'Bakiyesi',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capDebit1',
              bounds: JetRect(x: _debitX, y: 18, width: _moneyW, height: 10),
              text: 'Dönem',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capDebit2',
              bounds: JetRect(x: _debitX, y: 28, width: _moneyW, height: 10),
              text: 'Borç',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capCredit1',
              bounds: JetRect(x: _creditX, y: 18, width: _moneyW, height: 10),
              text: 'Dönem',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capCredit2',
              bounds: JetRect(x: _creditX, y: 28, width: _moneyW, height: 10),
              text: 'Alacak',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capClosing1',
              bounds: JetRect(x: _closingX, y: 18, width: _moneyW, height: 10),
              text: 'Kapanış',
              style: _captionStyle,
            ),
            TextElement(
              id: 'ph/capClosing2',
              bounds: JetRect(x: _closingX, y: 28, width: _moneyW, height: 10),
              text: 'Bakiyesi',
              style: _captionStyle,
            ),
            ShapeElement(
              id: 'ph/ruleBottom',
              bounds: JetRect(x: 0, y: 39, width: _contentWidth, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _grey),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pf',
          type: BandType.pageFooter,
          height: 18,
          elements: <ReportElement>[
            TextElement(
              id: 'pf/note',
              bounds: JetRect(x: 0, y: 4, width: 380, height: 10),
              text: 'Tutarlar TL. Borç bakiyeleri artı, alacak bakiyeleri '
                  'eksi gösterilir.',
              style: JetTextStyle(fontSize: 7, color: _grey),
            ),
            // No exported constant names PAGE_NUMBER or PAGE_COUNT, and no
            // helper builds this string; it is prose in the documentation.
            TextElement(
              id: 'pf/page',
              bounds: JetRect(x: 400, y: 4, width: 138, height: 10),
              text: 'Sayfa',
              style: JetTextStyle(
                fontSize: 7.5,
                color: _grey,
                align: JetTextAlign.right,
              ),
              expression:
                  r'"Sayfa " + $V{PAGE_NUMBER} + " / " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        title: Band(
          id: 'ttl',
          type: BandType.title,
          height: 56,
          elements: <ReportElement>[
            TextElement(
              id: 'ttl/firma',
              bounds: JetRect(x: 0, y: 0, width: 400, height: 16),
              text: 'firmaAdi',
              style: JetTextStyle(fontSize: 12, weight: JetFontWeight.bold),
              expression: r'$P{firmaAdi}',
            ),
            TextElement(
              id: 'ttl/baslik',
              bounds: JetRect(x: 0, y: 20, width: 300, height: 26),
              text: 'MİZAN',
              style: JetTextStyle(fontSize: 20, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'ttl/donem',
              bounds: JetRect(x: 300, y: 26, width: 238, height: 14),
              text: 'donem',
              style: JetTextStyle(fontSize: 10, align: JetTextAlign.right),
              expression: r'$P{donem}',
            ),
            TextElement(
              id: 'ttl/altBaslik',
              bounds: JetRect(x: 0, y: 46, width: _contentWidth, height: 10),
              text: 'Tek Düzen Hesap Planı — hesap sınıfı ve ana hesap '
                  'kırılımlı',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
          ],
        ),
        summary: Band(
          id: 'sum',
          type: BandType.summary,
          height: 62,
          elements: <ReportElement>[
            ShapeElement(
              id: 'sum/rule',
              bounds: JetRect(x: 0, y: 4, width: _contentWidth, height: 1.5),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: JetColor.black),
            ),
            TextElement(
              id: 'sum/label',
              bounds: JetRect(x: 0, y: 12, width: _labelW, height: 16),
              text: 'GENEL TOPLAM',
              style: JetTextStyle(
                fontSize: 10,
                weight: JetFontWeight.bold,
                align: JetTextAlign.right,
              ),
            ),
            TextElement(
              id: 'sum/opening',
              bounds: JetRect(x: _openingX, y: 12, width: _moneyW, height: 16),
              text: 'acilis',
              style: _grandTotalStyle,
              expression: _sumOpening,
              format: _money,
            ),
            TextElement(
              id: 'sum/debit',
              bounds: JetRect(x: _debitX, y: 12, width: _moneyW, height: 16),
              text: 'borc',
              style: _grandTotalStyle,
              expression: _sumDebit,
              format: _money,
            ),
            TextElement(
              id: 'sum/credit',
              bounds: JetRect(x: _creditX, y: 12, width: _moneyW, height: 16),
              text: 'alacak',
              style: _grandTotalStyle,
              expression: _sumCredit,
              format: _money,
            ),
            TextElement(
              id: 'sum/closing',
              bounds: JetRect(x: _closingX, y: 12, width: _moneyW, height: 16),
              text: 'kapanis',
              style: _grandTotalStyle,
              expression: _sumClosing,
              format: _money,
            ),
            ShapeElement(
              id: 'sum/ruleCheck',
              bounds: JetRect(x: 240, y: 32, width: 294, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _grey),
            ),
            TextElement(
              id: 'sum/checkLabel',
              bounds: JetRect(x: 0, y: 38, width: _labelW, height: 12),
              text: 'Fark (dönem borç − dönem alacak)',
              style: JetTextStyle(
                fontSize: 8,
                color: _grey,
                align: JetTextAlign.right,
              ),
            ),
            TextElement(
              id: 'sum/check',
              bounds: JetRect(x: _debitX, y: 38, width: _moneyW, height: 12),
              text: 'fark',
              style: JetTextStyle(
                fontSize: 8,
                weight: JetFontWeight.bold,
                align: JetTextAlign.right,
              ),
              expression: _difference,
              format: _money,
            ),
            TextElement(
              id: 'sum/checkNote',
              bounds: JetRect(x: 392, y: 38, width: 146, height: 12),
              text: 'Mizan tutuyorsa 0,00 okur.',
              style: JetTextStyle(fontSize: 7, color: _grey),
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            // --- Outer group: TDHP account class (one digit) ---
            GroupLevel(
              id: 'sinif',
              name: 'sinif',
              key: _classKey,
              // A class routinely spans pages; its heading reprints atop each
              // continuation so a reader who turns the page still knows which
              // class the rows belong to.
              reprintHeaderOnEachPage: true,
              header: Band(
                id: 'cls',
                type: BandType.groupHeader,
                height: 26,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 'cls/bg',
                    bounds:
                        JetRect(x: 0, y: 4, width: _contentWidth, height: 20),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _classFill),
                  ),
                  TextElement(
                    id: 'cls/name',
                    bounds: JetRect(x: 6, y: 7, width: 526, height: 15),
                    text: 'sinifAdi',
                    style:
                        JetTextStyle(fontSize: 11, weight: JetFontWeight.bold),
                    // The label is built from the code and the carried class
                    // name; the engine has no way to map a group key to a
                    // label, so every row repeats its class name.
                    expression: r'SUBSTRING($F{hesapKodu}, 0, 1) + " — " + '
                        r'$F{sinifAdi}',
                  ),
                ],
              ),
              footer: Band(
                id: 'clsF',
                type: BandType.groupFooter,
                height: 30,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 'clsF/rule',
                    bounds:
                        JetRect(x: 0, y: 2, width: _contentWidth, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                  TextElement(
                    id: 'clsF/label',
                    bounds: JetRect(x: 0, y: 7, width: _labelW, height: 14),
                    text: 'sinif toplami',
                    style: JetTextStyle(
                      fontSize: 9,
                      weight: JetFontWeight.bold,
                      align: JetTextAlign.right,
                    ),
                    expression: r'SUBSTRING($F{hesapKodu}, 0, 1) + " " + '
                        r'$F{sinifAdi} + " toplamı"',
                  ),
                  TextElement(
                    id: 'clsF/opening',
                    bounds: JetRect(
                        x: _openingX, y: 7, width: _moneyW, height: 14),
                    text: 'acilis',
                    style: _classTotalStyle,
                    expression: _sumOpening,
                    format: _money,
                  ),
                  TextElement(
                    id: 'clsF/debit',
                    bounds:
                        JetRect(x: _debitX, y: 7, width: _moneyW, height: 14),
                    text: 'borc',
                    style: _classTotalStyle,
                    expression: _sumDebit,
                    format: _money,
                  ),
                  TextElement(
                    id: 'clsF/credit',
                    bounds:
                        JetRect(x: _creditX, y: 7, width: _moneyW, height: 14),
                    text: 'alacak',
                    style: _classTotalStyle,
                    expression: _sumCredit,
                    format: _money,
                  ),
                  TextElement(
                    id: 'clsF/closing',
                    bounds: JetRect(
                        x: _closingX, y: 7, width: _moneyW, height: 14),
                    text: 'kapanis',
                    style: _classTotalStyle,
                    expression: _sumClosing,
                    format: _money,
                  ),
                ],
              ),
            ),
            // --- Inner group: TDHP main account (three digits) ---
            GroupLevel(
              id: 'anaHesap',
              name: 'anaHesap',
              key: _mainAccountKey,
              // A main account is the unit a reader scans, so keep its header,
              // its posting accounts and its subtotal on one page where they
              // fit. Nothing here is tall enough to need splitting.
              keepTogether: true,
              header: Band(
                id: 'acc',
                type: BandType.groupHeader,
                height: 18,
                elements: <ReportElement>[
                  TextElement(
                    id: 'acc/name',
                    bounds: JetRect(x: 0, y: 4, width: 400, height: 12),
                    text: 'anaHesapAdi',
                    style: JetTextStyle(
                      fontSize: 9,
                      weight: JetFontWeight.semiBold,
                    ),
                    expression: r'SUBSTRING($F{hesapKodu}, 0, 3) + "  " + '
                        r'$F{anaHesapAdi}',
                  ),
                ],
              ),
              footer: Band(
                id: 'accF',
                type: BandType.groupFooter,
                height: 22,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 'accF/rule',
                    bounds: JetRect(x: 240, y: 1, width: 294, height: 0.5),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                  TextElement(
                    id: 'accF/label',
                    bounds: JetRect(x: 0, y: 5, width: _labelW, height: 12),
                    text: 'ana hesap toplami',
                    style: JetTextStyle(
                      fontSize: 8,
                      weight: JetFontWeight.bold,
                      align: JetTextAlign.right,
                    ),
                    expression: r'$F{anaHesapAdi} + " toplamı"',
                  ),
                  TextElement(
                    id: 'accF/opening',
                    bounds: JetRect(
                        x: _openingX, y: 5, width: _moneyW, height: 12),
                    text: 'acilis',
                    style: _accountTotalStyle,
                    expression: _sumOpening,
                    format: _money,
                  ),
                  TextElement(
                    id: 'accF/debit',
                    bounds:
                        JetRect(x: _debitX, y: 5, width: _moneyW, height: 12),
                    text: 'borc',
                    style: _accountTotalStyle,
                    expression: _sumDebit,
                    format: _money,
                  ),
                  TextElement(
                    id: 'accF/credit',
                    bounds:
                        JetRect(x: _creditX, y: 5, width: _moneyW, height: 12),
                    text: 'alacak',
                    style: _accountTotalStyle,
                    expression: _sumCredit,
                    format: _money,
                  ),
                  TextElement(
                    id: 'accF/closing',
                    bounds: JetRect(
                        x: _closingX, y: 5, width: _moneyW, height: 12),
                    text: 'kapanis',
                    style: _accountTotalStyle,
                    expression: _sumClosing,
                    format: _money,
                  ),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
              id: 'det',
              type: BandType.detail,
              height: 13,
              elements: <ReportElement>[
                TextElement(
                  id: 'det/code',
                  // Indented under the main-account heading above it.
                  bounds: JetRect(x: 8, y: 1, width: 46, height: 11),
                  text: 'hesapKodu',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{hesapKodu}',
                ),
                TextElement(
                  id: 'det/name',
                  bounds: JetRect(x: _nameX, y: 1, width: _nameW, height: 11),
                  text: 'hesapAdi',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{hesapAdi}',
                ),
                TextElement(
                  id: 'det/opening',
                  bounds:
                      JetRect(x: _openingX, y: 1, width: _moneyW, height: 11),
                  text: 'acilis',
                  style: _moneyStyle,
                  expression: r'$F{acilis}',
                  format: _money,
                ),
                TextElement(
                  id: 'det/debit',
                  bounds:
                      JetRect(x: _debitX, y: 1, width: _moneyW, height: 11),
                  text: 'borc',
                  style: _moneyStyle,
                  expression: r'$F{borc}',
                  format: _money,
                ),
                TextElement(
                  id: 'det/credit',
                  bounds:
                      JetRect(x: _creditX, y: 1, width: _moneyW, height: 11),
                  text: 'alacak',
                  style: _moneyStyle,
                  expression: r'$F{alacak}',
                  format: _money,
                ),
                TextElement(
                  id: 'det/closing',
                  bounds:
                      JetRect(x: _closingX, y: 1, width: _moneyW, height: 11),
                  text: 'kapanis',
                  style: _moneyStyle,
                  expression: _rowClosing,
                  format: _money,
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// A column caption in the running head.
const JetTextStyle _captionStyle = JetTextStyle(
  fontSize: 7.5,
  weight: JetFontWeight.bold,
  align: JetTextAlign.right,
);

/// A detail row's money cell.
const JetTextStyle _moneyStyle = JetTextStyle(
  fontSize: 8,
  align: JetTextAlign.right,
);

/// A main-account subtotal's money cell.
const JetTextStyle _accountTotalStyle = JetTextStyle(
  fontSize: 8,
  weight: JetFontWeight.bold,
  align: JetTextAlign.right,
);

/// A class subtotal's money cell.
const JetTextStyle _classTotalStyle = JetTextStyle(
  fontSize: 9,
  weight: JetFontWeight.bold,
  align: JetTextAlign.right,
);

/// A grand-total money cell.
const JetTextStyle _grandTotalStyle = JetTextStyle(
  fontSize: 10,
  weight: JetFontWeight.bold,
  align: JetTextAlign.right,
);
