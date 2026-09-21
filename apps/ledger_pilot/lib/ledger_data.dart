/// The pilot's data layer: a synthetic but internally consistent general
/// ledger over `chart_of_accounts.dart`, plus the three spellings of its
/// schema the public API asks for.
///
/// ## Money
///
/// Every amount is held internally as a whole number of **quarter-lira** and
/// divided by four on the way out. That is not an accounting convention; it is
/// a concession to the engine. `JetNumber` holds a `double` and every fold in
/// the library is double arithmetic, so a column of kuruş amounts that ought
/// to foot to exactly zero instead foots to something like `-6e-8`, which
/// `#,##0.00` renders as `-0,00`. A quarter of a lira is a dyadic fraction, so
/// `q / 4.0` is exact and every total in this report foots to the kuruş with
/// no residue. Amounts still end in `,00`, `,25`, `,50` or `,75`, so they read
/// like money rather than like round numbers.
///
/// ## The invariants
///
/// These hold for the generated rows by construction, not by checking
/// afterwards, and the report is designed so that a reader can verify them
/// from the printed page:
///
/// 1. **Every movement is a balanced journal entry.** A movement is generated
///    from a template with debit legs and credit legs; both sides are split
///    from the same amount with the remainder assigned to the last leg, so
///    each entry's debits equal its credits exactly. Therefore
///    `Σ dönem borç == Σ dönem alacak` over the whole ledger, and the
///    "Fark" cell in the grand total prints `0,00`.
/// 2. **Opening balances net to zero.** Balances are signed — a debit balance
///    is positive, a credit balance negative — and `570.01 Geçmiş Yıllar
///    Kârları` carries the balancing figure, exactly as retained earnings does
///    in a real opening balance sheet. Therefore `Σ açılış bakiyesi == 0`.
/// 3. **Income-statement accounts open at zero.** Classes 6 and 7 carry no
///    opening balance: the period is a fresh one.
/// 4. **Closing follows from opening plus movements.** `kapanış = açılış +
///    borç − alacak` per account. The *report* computes this, per row and per
///    subtotal; nothing here precomputes it. Combined with (1) and (2),
///    `Σ kapanış bakiyesi == 0` as well.
///
/// ## Ordering
///
/// The engine does not sort. A `GroupLevel` breaks when its key changes
/// between consecutive rows, so an unsorted ledger produces the same class
/// heading several times with no diagnostic anywhere. [buildLedgerRows] sorts
/// by account code before returning, and that sort is load-bearing.
library;

import 'package:jet_print/jet_print.dart';

import 'chart_of_accounts.dart';

/// The ledger's field schema, in column order.
///
/// This is the one place the shape is written down. The other two spellings
/// the public API wants — [trialBalanceSchema] for `validate` and
/// [knownLedgerFields] for `RenderOptions.knownFields` — are derived from it
/// below, because nothing in the library derives them for you.
const List<FieldDef> ledgerFields = <FieldDef>[
  FieldDef('hesapKodu', type: JetFieldType.string),
  FieldDef('hesapAdi', type: JetFieldType.string),
  FieldDef('anaHesapAdi', type: JetFieldType.string),
  FieldDef('sinifAdi', type: JetFieldType.string),
  FieldDef('acilis', type: JetFieldType.double),
  FieldDef('borc', type: JetFieldType.double),
  FieldDef('alacak', type: JetFieldType.double),
];

/// The same schema as a [JetDataSchema], which is what `validate`'s optional
/// `schema:` argument takes.
const JetDataSchema trialBalanceSchema = JetDataSchema(
  name: 'Mizan',
  fields: ledgerFields,
);

/// The same schema again as a name set, which is what
/// `RenderOptions.knownFields` takes. Supplying it turns a mistyped field name
/// from a silently empty cell into a visible `#ERROR`.
final Set<String> knownLedgerFields = <String>{
  for (final FieldDef field in ledgerFields) field.name,
};

/// Builds the ledger, sorted by account code.
///
/// Deterministic: same code in, same rows out, on every platform and every
/// run. Nothing here reads a clock, a locale or a real random source.
List<Map<String, Object?>> buildLedgerRows() {
  final Map<String, int> debitQuarters = <String, int>{};
  final Map<String, int> creditQuarters = <String, int>{};
  final _Rng rng = _Rng(_seed);

  for (final _EntryTemplate template in _journalTemplates) {
    for (int i = 0; i < template.occurrences; i++) {
      final int amount = _amountQuarters(rng, template.minTl, template.maxTl);
      _post(debitQuarters, template.debits, amount);
      _post(creditQuarters, template.credits, amount);
    }
  }

  // Invariant 2: retained earnings absorbs whatever the rest of the opening
  // balance sheet does not net out, so the opening column sums to zero.
  final int plug = -_openingQuarters.values
      .fold<int>(0, (int sum, int value) => sum + value);
  final Map<String, int> openings = <String, int>{
    ..._openingQuarters,
    _retainedEarnings: plug,
  };

  // A posting to a code that is not in the chart would break invariant 1
  // silently — the two sides of the entry would still balance, but one of them
  // would never reach a row. Asserts compile out of a release build.
  assert(
    _unknownCodes(<String>{
      ...debitQuarters.keys,
      ...creditQuarters.keys,
    }).isEmpty,
    'the journal templates post to codes that are not in the chart',
  );

  final List<PostingAccount> ordered = <PostingAccount>[...postingAccounts]
    ..sort((PostingAccount a, PostingAccount b) => a.code.compareTo(b.code));

  return <Map<String, Object?>>[
    for (final PostingAccount account in ordered)
      <String, Object?>{
        'hesapKodu': account.code,
        'hesapAdi': account.name,
        'anaHesapAdi': mainAccountNames[account.mainAccountCode]!,
        'sinifAdi': accountClassNames[account.classCode]!,
        'acilis': (openings[account.code] ?? 0) / 4.0,
        'borc': (debitQuarters[account.code] ?? 0) / 4.0,
        'alacak': (creditQuarters[account.code] ?? 0) / 4.0,
      },
  ];
}

/// Codes in [posted] that no posting account in the chart carries.
Set<String> _unknownCodes(Set<String> posted) {
  final Set<String> known = <String>{
    for (final PostingAccount account in postingAccounts) account.code,
  };
  return posted.difference(known);
}

/// The generator seed. Any value gives a balanced ledger; this one is the
/// pilot's period start, so the figures are stable across runs and reviews.
const int _seed = 20260101;

/// The account that carries the opening balance sheet's balancing figure.
const String _retainedEarnings = '570.01';

/// Splits [amount] across [legs] by their declared shares and adds each piece
/// to [into], giving the remainder to the last leg.
///
/// The remainder rule is what makes invariant 1 exact: the pieces sum to
/// [amount] whatever the shares round to, so a three-legged VAT entry still
/// balances to the quarter-lira.
void _post(Map<String, int> into, List<_Leg> legs, int amount) {
  int assigned = 0;
  for (int i = 0; i < legs.length; i++) {
    final int piece = i == legs.length - 1
        ? amount - assigned
        : amount * legs[i].share ~/ 100;
    assigned += piece;
    into[legs[i].code] = (into[legs[i].code] ?? 0) + piece;
  }
}

/// An amount in quarter-lira, between [minTl] and [maxTl] whole lira, with a
/// quarter-lira tail so the printed figure carries kuruş.
int _amountQuarters(_Rng rng, int minTl, int maxTl) {
  final int lira = minTl + (maxTl - minTl) * rng.next(1000) ~/ 1000;
  return lira * 4 + rng.next(4);
}

/// A deterministic Lehmer generator, modulus 65537.
///
/// Small on purpose: every intermediate stays well inside 2^53, so the same
/// sequence comes out on the Dart VM and on the web, where an `int` is a
/// double. `next` is slightly biased for bounds that do not divide 65537,
/// which does not matter for sample figures.
class _Rng {
  /// Creates a generator seeded at [_state].
  _Rng(this._state);

  int _state;

  /// The next value in `[0, bound)`.
  int next(int bound) {
    _state = (_state * 75 + 74) % 65537;
    return _state % bound;
  }
}

/// One leg of a journal-entry template: the posting account [code] and its
/// [share] of the entry amount, in per cent. A template's debit shares and its
/// credit shares each total 100.
typedef _Leg = ({String code, int share});

/// A recurring journal entry: what it debits, what it credits, how often it
/// occurs in the period, and the range its amount is drawn from.
class _EntryTemplate {
  /// Creates a template.
  const _EntryTemplate({
    required this.debits,
    required this.credits,
    required this.occurrences,
    required this.minTl,
    required this.maxTl,
  });

  /// The debit legs; shares total 100.
  final List<_Leg> debits;

  /// The credit legs; shares total 100.
  final List<_Leg> credits;

  /// How many times this entry is posted over the period.
  final int occurrences;

  /// The low end of the amount range, in whole lira.
  final int minTl;

  /// The high end of the amount range, in whole lira.
  final int maxTl;
}

/// The period's recurring entries. Ordinary trading for a mid-sized Turkish
/// trading company: sales and their VAT, collections, purchases and payments,
/// payroll and its withholdings, overheads, financing, and a handful of
/// capital movements.
const List<_EntryTemplate> _journalTemplates = <_EntryTemplate>[
  // Yurtiçi satış: alıcıya borç, satış ve hesaplanan KDV alacak.
  _EntryTemplate(
    debits: <_Leg>[(code: '120.01', share: 100)],
    credits: <_Leg>[
      (code: '600.01', share: 50),
      (code: '600.02', share: 33),
      (code: '391.01', share: 17),
    ],
    occurrences: 14,
    minTl: 40000,
    maxTl: 180000,
  ),
  // Kredi kartlı hizmet satışı.
  _EntryTemplate(
    debits: <_Leg>[(code: '108.01', share: 100)],
    credits: <_Leg>[
      (code: '600.03', share: 83),
      (code: '391.02', share: 17),
    ],
    occurrences: 10,
    minTl: 8000,
    maxTl: 35000,
  ),
  // Alıcıdan banka tahsilatı.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '102.01', share: 60),
      (code: '102.02', share: 40),
    ],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 16,
    minTl: 30000,
    maxTl: 150000,
  ),
  // Alıcıdan çek alınması.
  _EntryTemplate(
    debits: <_Leg>[(code: '101.01', share: 100)],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 8,
    minTl: 20000,
    maxTl: 90000,
  ),
  // Çekin bankadan tahsili.
  _EntryTemplate(
    debits: <_Leg>[(code: '102.03', share: 100)],
    credits: <_Leg>[(code: '101.01', share: 100)],
    occurrences: 7,
    minTl: 15000,
    maxTl: 70000,
  ),
  // Alıcıdan senet alınması.
  _EntryTemplate(
    debits: <_Leg>[(code: '121.01', share: 100)],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 5,
    minTl: 25000,
    maxTl: 80000,
  ),
  // İhracat satışı (KDV'siz).
  _EntryTemplate(
    debits: <_Leg>[(code: '120.02', share: 100)],
    credits: <_Leg>[(code: '601.01', share: 100)],
    occurrences: 9,
    minTl: 60000,
    maxTl: 260000,
  ),
  // Yurtdışı alacakta kur farkı geliri.
  _EntryTemplate(
    debits: <_Leg>[(code: '120.02', share: 100)],
    credits: <_Leg>[(code: '649.01', share: 100)],
    occurrences: 6,
    minTl: 3000,
    maxTl: 22000,
  ),
  // Döviz kasasında kambiyo zararı.
  _EntryTemplate(
    debits: <_Leg>[(code: '656.01', share: 100)],
    credits: <_Leg>[(code: '100.03', share: 100)],
    occurrences: 5,
    minTl: 2000,
    maxTl: 14000,
  ),
  // Yurtiçi mal alımı ve indirilecek KDV.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '153.01', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '320.01', share: 100)],
    occurrences: 12,
    minTl: 45000,
    maxTl: 200000,
  ),
  // İthalat alımı.
  _EntryTemplate(
    debits: <_Leg>[(code: '153.01', share: 100)],
    credits: <_Leg>[(code: '320.02', share: 100)],
    occurrences: 6,
    minTl: 80000,
    maxTl: 300000,
  ),
  // Satıcıya banka ödemesi.
  _EntryTemplate(
    debits: <_Leg>[(code: '320.01', share: 100)],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 13,
    minTl: 40000,
    maxTl: 170000,
  ),
  // Satıcıya senet verilmesi.
  _EntryTemplate(
    debits: <_Leg>[(code: '320.02', share: 100)],
    credits: <_Leg>[(code: '321.01', share: 100)],
    occurrences: 4,
    minTl: 50000,
    maxTl: 150000,
  ),
  // Satılan ticari mal maliyeti.
  _EntryTemplate(
    debits: <_Leg>[(code: '621.01', share: 100)],
    credits: <_Leg>[(code: '153.01', share: 100)],
    occurrences: 12,
    minTl: 35000,
    maxTl: 160000,
  ),
  // Satıştan iade.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '610.01', share: 83),
      (code: '391.02', share: 17),
    ],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 4,
    minTl: 5000,
    maxTl: 25000,
  ),
  // Ücret tahakkuku ve kesintileri.
  _EntryTemplate(
    debits: <_Leg>[(code: '770.01', share: 100)],
    credits: <_Leg>[
      (code: '335.01', share: 63),
      (code: '361.01', share: 25),
      (code: '360.01', share: 10),
      (code: '360.02', share: 2),
    ],
    occurrences: 12,
    minTl: 180000,
    maxTl: 240000,
  ),
  // Net ücret ödemesi.
  _EntryTemplate(
    debits: <_Leg>[(code: '335.01', share: 100)],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 12,
    minTl: 110000,
    maxTl: 140000,
  ),
  // SGK prim ödemesi.
  _EntryTemplate(
    debits: <_Leg>[(code: '361.01', share: 100)],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 12,
    minTl: 40000,
    maxTl: 60000,
  ),
  // Stopaj ve damga vergisi ödemesi.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '360.01', share: 85),
      (code: '360.02', share: 15),
    ],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 12,
    minTl: 20000,
    maxTl: 35000,
  ),
  // Kira gideri.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '770.02', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 12,
    minTl: 45000,
    maxTl: 55000,
  ),
  // Elektrik, su ve doğalgaz.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '770.03', share: 90),
      (code: '191.02', share: 10),
    ],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 12,
    minTl: 12000,
    maxTl: 28000,
  ),
  // Haberleşme gideri.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '770.04', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 12,
    minTl: 4000,
    maxTl: 9000,
  ),
  // Üç aylık amortisman ayrımı.
  _EntryTemplate(
    debits: <_Leg>[(code: '770.05', share: 100)],
    credits: <_Leg>[
      (code: '257.01', share: 30),
      (code: '257.02', share: 45),
      (code: '257.03', share: 25),
    ],
    occurrences: 4,
    minTl: 90000,
    maxTl: 130000,
  ),
  // Denetim ve müşavirlik.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '770.06', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '320.01', share: 100)],
    occurrences: 4,
    minTl: 25000,
    maxTl: 45000,
  ),
  // Vergi, resim ve harçlar.
  _EntryTemplate(
    debits: <_Leg>[(code: '770.07', share: 100)],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 6,
    minTl: 6000,
    maxTl: 18000,
  ),
  // Reklam ve tanıtım.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '760.01', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '320.01', share: 100)],
    occurrences: 8,
    minTl: 20000,
    maxTl: 70000,
  ),
  // Nakliye gideri.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '760.02', share: 83),
      (code: '191.02', share: 17),
    ],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 10,
    minTl: 8000,
    maxTl: 30000,
  ),
  // Kredi faiz tahakkuku.
  _EntryTemplate(
    debits: <_Leg>[(code: '780.01', share: 100)],
    credits: <_Leg>[(code: '300.01', share: 100)],
    occurrences: 12,
    minTl: 30000,
    maxTl: 60000,
  ),
  // Banka masrafları.
  _EntryTemplate(
    debits: <_Leg>[(code: '780.02', share: 100)],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 12,
    minTl: 1500,
    maxTl: 5000,
  ),
  // Vadeli mevduat faizi.
  _EntryTemplate(
    debits: <_Leg>[(code: '102.04', share: 100)],
    credits: <_Leg>[(code: '642.01', share: 100)],
    occurrences: 12,
    minTl: 25000,
    maxTl: 70000,
  ),
  // Dönem sonu gider tahakkuku.
  _EntryTemplate(
    debits: <_Leg>[(code: '632.01', share: 100)],
    credits: <_Leg>[(code: '381.01', share: 100)],
    occurrences: 6,
    minTl: 10000,
    maxTl: 40000,
  ),
  // Alacağın şüpheli hale gelmesi.
  _EntryTemplate(
    debits: <_Leg>[(code: '128.01', share: 100)],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 3,
    minTl: 15000,
    maxTl: 60000,
  ),
  // Müşteriden alınan sipariş avansı.
  _EntryTemplate(
    debits: <_Leg>[(code: '102.01', share: 100)],
    credits: <_Leg>[(code: '340.01', share: 100)],
    occurrences: 5,
    minTl: 30000,
    maxTl: 120000,
  ),
  // Satıcıya verilen sipariş avansı.
  _EntryTemplate(
    debits: <_Leg>[(code: '159.01', share: 100)],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 5,
    minTl: 20000,
    maxTl: 90000,
  ),
  // Peşin ödenen sigorta primi.
  _EntryTemplate(
    debits: <_Leg>[(code: '180.01', share: 100)],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 2,
    minTl: 40000,
    maxTl: 80000,
  ),
  // Bilgisayar ve donanım alımı.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '255.02', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 4,
    minTl: 25000,
    maxTl: 90000,
  ),
  // Büro demirbaşı alımı.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '255.01', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '320.01', share: 100)],
    occurrences: 3,
    minTl: 12000,
    maxTl: 45000,
  ),
  // Üretim makinesi alımı, rotatif kredi ile.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '253.01', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '300.02', share: 100)],
    occurrences: 2,
    minTl: 250000,
    maxTl: 600000,
  ),
  // Binek araç alımı.
  _EntryTemplate(
    debits: <_Leg>[(code: '254.01', share: 100)],
    credits: <_Leg>[(code: '102.02', share: 100)],
    occurrences: 1,
    minTl: 900000,
    maxTl: 1400000,
  ),
  // Yazılım lisansı alımı.
  _EntryTemplate(
    debits: <_Leg>[
      (code: '260.01', share: 83),
      (code: '191.01', share: 17),
    ],
    credits: <_Leg>[(code: '320.02', share: 100)],
    occurrences: 3,
    minTl: 30000,
    maxTl: 90000,
  ),
  // Grup şirketine cari hesap aktarımı.
  _EntryTemplate(
    debits: <_Leg>[(code: '120.03', share: 100)],
    credits: <_Leg>[(code: '102.01', share: 100)],
    occurrences: 4,
    minTl: 40000,
    maxTl: 150000,
  ),
  // Şube kasasına nakit transferi.
  _EntryTemplate(
    debits: <_Leg>[(code: '100.02', share: 100)],
    credits: <_Leg>[(code: '102.05', share: 100)],
    occurrences: 8,
    minTl: 10000,
    maxTl: 40000,
  ),
  // Merkez kasada nakit tahsilat.
  _EntryTemplate(
    debits: <_Leg>[(code: '100.01', share: 100)],
    credits: <_Leg>[(code: '120.01', share: 100)],
    occurrences: 9,
    minTl: 5000,
    maxTl: 30000,
  ),
  // Kasadan bankaya yatırma.
  _EntryTemplate(
    debits: <_Leg>[(code: '102.05', share: 100)],
    credits: <_Leg>[(code: '100.01', share: 100)],
    occurrences: 8,
    minTl: 8000,
    maxTl: 35000,
  ),
  // Aylık KDV mahsubu.
  _EntryTemplate(
    debits: <_Leg>[(code: '391.01', share: 100)],
    credits: <_Leg>[(code: '191.01', share: 100)],
    occurrences: 6,
    minTl: 20000,
    maxTl: 40000,
  ),
];

/// Opening balances in quarter-lira, signed: a debit balance is positive, a
/// credit balance negative.
///
/// `570.01` is deliberately absent — it is computed as the balancing figure in
/// [buildLedgerRows]. So are every class 6 and class 7 account, which open at
/// zero because the period is a fresh one, and the two VAT accounts, which
/// were cleared at the previous period end.
const Map<String, int> _openingQuarters = <String, int>{
  '100.01': 193000,
  '100.02': 49922,
  '100.03': 345283,
  '101.01': 616000,
  '101.02': 250000,
  '102.01': 13674561,
  '102.02': 13061242,
  '102.03': 391383,
  '102.04': 3000000,
  '102.05': 164880,
  '108.01': 135041,
  '120.01': 5138000,
  '120.02': 2568722,
  '120.03': 872000,
  '121.01': 705803,
  '128.01': 216800,
  '153.01': 5849241,
  '159.01': 352000,
  '180.01': 98400,
  '252.01': 13000000,
  '253.01': 8562000,
  '253.02': 1547002,
  '254.01': 4480000,
  '254.02': 7501600,
  '255.01': 1251443,
  '255.02': 1795681,
  '257.01': -3250000,
  '257.02': -4985200,
  '257.03': -1579522,
  '260.01': 1073600,
  '300.01': -5800000,
  '300.02': -2720000,
  '320.01': -7384882,
  '320.02': -3693641,
  '321.01': -1648000,
  '335.01': -746960,
  '340.01': -1024000,
  '360.01': -377283,
  '360.02': -49920,
  '361.01': -914602,
  '381.01': -304000,
  '500.01': -20000000,
};
