/// The playground's rendered sales-ledger example (spec 040): a
/// [JetPagedDataSource] generates ~20k transactions on demand, one page at a
/// time, and the public engine renders them into a multi-page report. The whole
/// integration — paged source + render — goes through
/// `package:jet_print/jet_print.dart` only.
///
/// The data is **deterministic**: every value derives from the row index (no
/// clock, no randomness), and amounts are multiples of 0.25 so the rendered
/// `SUM` is exact and equals a test-side fold.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'ledger_sample.dart';

/// The demo's logical row count.
const int kLedgerRowCount = 20000;

/// Rows fetched per page by [ledgerDataSource]. 20000 is an exact multiple, so
/// the feed ends on an empty trailing page — exercising that path live.
const int kLedgerPageSize = 250;

/// Sample item names, chosen by index.
const List<String> _items = <String>[
  'Espresso',
  'Flat White',
  'Croissant',
  'Bagel',
  'Orange Juice',
  'Club Sandwich',
  'Caesar Salad',
  'Cheesecake',
];

/// A deterministic, non-periodic "spin" of row [index] with a per-column [salt]:
/// `(index * 131 + salt * 101) mod 1009`. 1009 is prime (so coprime to the
/// rows-per-page), which keeps every column from marching in lockstep with the
/// page size — each page looks freshly varied instead of repeating the same
/// sequence. Each value stays a pure function of the index (no `Random`, fully
/// reproducible; identical on web and the VM, since no intermediate exceeds 2^53
/// and no bitwise ops are used).
int _spin(int index, int salt) => (index * 131 + salt * 101) % 1009;

/// The quantity for row [index] (1..5), spun so it does not cycle with the page.
int _qtyAt(int index) => _spin(index, 2) % 5 + 1;

/// The unit price for row [index] — a multiple of 0.25 in [0.25, 10.00].
double _unitPriceAt(int index) => (_spin(index, 3) % 40 + 1) * 0.25;

/// The status for row [index]: mostly PAID, with the occasional REFUND/VOID,
/// spread non-periodically.
String _statusAt(int index) {
  final int s = _spin(index, 4) % 20;
  if (s == 0) return 'VOID';
  if (s <= 2) return 'REFUND';
  return 'PAID';
}

/// The line amount for row [index] = qty × unitPrice — a multiple of 0.25, so
/// the report's `SUM($F{amount})` is exact in IEEE-754.
double ledgerAmountAt(int index) => _qtyAt(index) * _unitPriceAt(index);

/// A deterministic `yyyy-MM-dd HH:mm` timestamp for row [index] (one minute
/// apart from a fixed epoch — no `DateTime.now()`).
String _timeAt(int index) => DateTime.utc(2026, 1, 1)
    .add(Duration(minutes: index))
    .toIso8601String()
    .substring(0, 16)
    .replaceFirst('T', ' ');

/// The full row map for transaction [index].
Map<String, Object?> ledgerRowAt(int index) => <String, Object?>{
      'time': _timeAt(index),
      'receiptNo': 'R-${100000 + index}',
      'item': _items[_spin(index, 1) % _items.length],
      'qty': _qtyAt(index),
      'unitPrice': _unitPriceAt(index),
      'amount': ledgerAmountAt(index),
      'status': _statusAt(index),
    };

/// Page [pageIndex] of the feed: up to [kLedgerPageSize] rows, fewer (or empty)
/// once the feed is exhausted — the signal [JetPagedDataSource] stops on.
List<Map<String, Object?>> ledgerFetchPage(int pageIndex) {
  final int start = pageIndex * kLedgerPageSize;
  if (start >= kLedgerRowCount) return const <Map<String, Object?>>[];
  final int end = (start + kLedgerPageSize) > kLedgerRowCount
      ? kLedgerRowCount
      : start + kLedgerPageSize;
  return <Map<String, Object?>>[
    for (int i = start; i < end; i++) ledgerRowAt(i),
  ];
}

/// The demo data source: a lazily-paged feed that never holds all rows at once.
JetDataSource ledgerDataSource() => JetPagedDataSource(
      fields: ledgerSchema.fields,
      pageSize: kLedgerPageSize,
      fetchPage: ledgerFetchPage,
    );

/// The flat set of every schema field name (for schema-aware render).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };

/// Renders the ledger definition against the paged source (or an injected
/// [source]/[definition], used by the parity test).
RenderedReport renderLedgerDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? ledgerSampleDefinition(),
      source ?? ledgerDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(ledgerSchema.fields),
        fonts: fonts,
      ),
    );
