/// Bounds and row-tags per-row *data* diagnostics during a fill (spec E2).
///
/// A fill over a large, dirty dataset can encounter the same data fault on
/// thousands of rows. Recording one diagnostic per occurrence would grow an
/// unbounded list (the very memory blow-up resilience is meant to prevent),
/// while the engine's historical global-dedup hides *where* the fault is. This
/// budget threads the current master-row position into each per-row data
/// diagnostic, dedups repeats *within a row* by a caller [key], and caps the
/// total emitted at [kMaxPerRowDataDiagnostics] — emitting a single trailing
/// summary at [finish] when any were suppressed.
///
/// What actually routes through here, as of the current call sites:
/// a `$F{}` to a **field** the row's schema does not declare
/// (`fill_eval_context.dart` → `resolveField`, key `field:<name>`), a non-row
/// entry inside a collection, and every non-numeric value skipped by an
/// aggregate. A missing field is structural, not per-row — but at scale it
/// recurs on every row, so it is budgeted and row-tagged like the rest. No
/// production path reaches the once-only `warnedFields` fallback: every fill
/// builds a budget (`report_filler.dart`) and passes it to each context, and
/// the one budget-less construction — `scanPageScoped`'s row-less probe —
/// returns from `resolveField` before it. Tests are what keep it exercised.
///
/// Still deduped-once on their own paths: a **collection** field absent from
/// the schema or not resolving to a list (`report_filler.dart` →
/// `childRowsOf`, via `warnedCollections`), and definition/parse diagnostics.
library;

import 'report_diagnostics.dart';

/// Row-aware, bounded sink wrapper for per-row data diagnostics.
class DiagnosticBudget {
  /// Creates a budget that records into [_sink].
  DiagnosticBudget(this._sink);

  /// The maximum number of per-row data diagnostics recorded before the rest
  /// are counted and summarized at [finish] (spec E2, FR-E2-002).
  static const int kMaxPerRowDataDiagnostics = 100;

  final ReportDiagnostics _sink;
  int _row = 0;
  int _emitted = 0;
  int _suppressed = 0;
  final Set<String> _seenThisRow = <String>{};

  /// The current 1-based master-row position. Setting a new value clears the
  /// within-row dedup memory so the same [key] can be reported again next row.
  set row(int value) {
    if (value != _row) {
      _row = value;
      _seenThisRow.clear();
    }
  }

  int get row => _row;

  /// Records one per-row data issue, deduped by [key] within the current row
  /// and bounded by [kMaxPerRowDataDiagnostics]. The recorded message is
  /// prefixed with the row position; [severity] defaults to warning.
  void recordRowIssue(
    String key,
    String message, {
    DiagnosticSeverity severity = DiagnosticSeverity.warning,
    String? elementId,
  }) {
    if (!_seenThisRow.add(key)) return; // already reported for this row
    if (_emitted >= kMaxPerRowDataDiagnostics) {
      _suppressed++;
      return;
    }
    _emitted++;
    _sink
        .add(Diagnostic(severity, 'Row $_row: $message', elementId: elementId));
  }

  /// Emits a single summary [DiagnosticSeverity.info] when any per-row data
  /// issues were suppressed; a no-op otherwise. Call once at fill completion.
  void finish() {
    if (_suppressed > 0) {
      _sink.info('… and $_suppressed more row-level data issue(s) were '
          'suppressed (showing first $kMaxPerRowDataDiagnostics)');
    }
  }
}
