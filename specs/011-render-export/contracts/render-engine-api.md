# Public API & Behavior Contract — Render Report (JetReportEngine)

Authoritative public surface for slice 011. Everything here is reachable **only** through `package:jet_print/jet_print.dart` (Constitution I; SC-001); `src/` stays private. Signatures are indicative Dart; the binding contract is the **behavior** + **test groups**.

## 1. Public surface added by this slice

```dart
// --- Render engine (NEW) ---
class JetReportEngine {
  const JetReportEngine();

  /// Fills [template] with [source]'s records (and [options]), paginates, and
  /// returns a lazily-paginated [RenderedReport]. Never throws on malformed
  /// data — problems surface as diagnostics. Deterministic over
  /// (template, data, parameters, locale).
  RenderedReport render(
    ReportTemplate template,
    JetDataSource source, {
    RenderOptions options = const RenderOptions(),
  });
}

class RenderOptions {
  const RenderOptions({
    this.parameters = const <String, Object?>{},
    this.locale = const Locale('en'), // documented neutral default
  });
  final Map<String, Object?> parameters; // FR-012
  final Locale locale;                   // FR-012a — explicit, not the UI locale
}

class RenderedReport {
  int get pageCount;                  // total pages (boundary pass)
  RenderedPage pageAt(int index);     // FR-021 — lazy build + cache
  ReportDiagnostics get diagnostics;  // merged fill + layout (FR-013)
}

class RenderedPage {
  int get index;
  PageFrame get frame;                // shared, backend-agnostic primitives
}

// --- Preview widget (NEW) ---
class JetReportPreview extends StatefulWidget {
  const JetReportPreview({
    super.key,
    required this.report,
    this.initialPage = 0,
  });
  final RenderedReport report;
  final int initialPage;
}

// --- Data-source API (PROMOTED — code unchanged, FR-011) ---
abstract class JetDataSource { DataSet open([Map<String, Object?> params]); }
class JetInMemoryDataSource implements JetDataSource { /* rows + optional schema */ }
class JetJsonDataSource    implements JetDataSource { /* JSON array-of-objects */ }
class JetObjectDataSource<T> implements JetDataSource { /* List<T> + schema + extractor */ }
abstract class DataSet { bool moveNext(); DataRow get current; List<FieldDef> get fields; void close(); }
class DataRow { Object? field(String name); bool hasField(String name); }

// --- Diagnostics (PROMOTED, FR-013) ---
enum DiagnosticSeverity { info, warning, error }
class Diagnostic { final DiagnosticSeverity severity; final String message; final String? elementId; }
class ReportDiagnostics { Iterable<Diagnostic> get entries; /* + severity helpers */ }
```

`FieldDef` / `JetFieldType` are already public (009). `ReportTemplate`, `PageFrame` consumers re-use existing public/promoted types.

## 2. Behavioral contracts

### C1 — Fill resolves tokens to values (FR-003; US1)
Given a template whose elements bind `$F{}`/`$P{}`/`$V{}`, `render` returns pages in which **every** bound element shows its **evaluated value** — zero residual tokens (SC-002).

### C2 — Master/detail + aggregates (FR-004/FR-005/FR-006; US2)
A collection-bound band repeats once per child record at arbitrary nesting depth; variables/aggregates compute at their reset scope (group + grand total); group header/footer render at key boundaries. Invoice total equals the exact sum of line amounts (SC-002).

### C3 — Pagination (FR-007; US1)
Content splits only at allowed band boundaries; page header/footer repeat on every page; `pageCount` matches content; `PAGE_NUMBER`/`PAGE_COUNT` resolve correctly (SC-005).

### C4 — Lazy first page (FR-021; SC-009)
`render(...).pageAt(0)` produces a viewable first page **without** constructing frames for other pages. For a 1,000-record dataset, first page is viewable in < 2 s on the reference desktop. `pageAt(i)` builds on demand and caches.

### C5 — Lazy ≡ eager (Constitution IV; SC-004)
`pageAt(i).frame` is byte-identical to the i-th frame produced by the preserved eager `layout()` wrapper. Re-rendering identical inputs yields byte-identical frames (determinism).

### C6 — WYSIWYG (FR-009; SC-003)
The preview paints each page through the **same** `paintFrame`→`CanvasPainter`→`PageFrame` path as the designer. Element geometry/fonts/styles/page format match the design surface for the same template (golden parity, light + dark).

### C7 — Explicit locale (FR-012a)
Number/date/currency formatting follows `RenderOptions.locale`, independent of the ambient/app UI locale. The same template + data rendered under two locales differ only in locale-sensitive formatting.

### C8 — Data-source parity (FR-011; SC-006)
The same logical dataset (incl. a nested collection) supplied via in-memory, JSON, and object-backed sources yields **identical** rendered output.

### C9 — Diagnostics, no crash (FR-013/FR-014; SC-007)
Unknown field, missing parameter, unresolved image, and empty dataset each produce a **specific** diagnostic identifying the element/band and the problem, and a **non-crashing** best-effort render (empty/placeholder fallback for the offending element; surrounding content renders normally). 0 unhandled crashes across the malformed-input matrix.

### C10 — Images (FR-012b)
Image elements render from host-supplied **bytes** (via the data source / embedded). A URL-only image source renders a placeholder + emits a diagnostic. The library performs no image I/O (FR-015).

### C11 — Preview interaction (FR-008/FR-017/FR-018; US1)
Read-only viewer: prev/next navigation (bounded), "page X of N" indicator, fit-to-width sizing. Chrome localized en/de/tr with English fallback; keyboard-operable with accessible names.

### C12 — Encapsulation & serialization (Constitution I/V; FR-016)
All symbols above are reachable solely via `package:jet_print/jet_print.dart`; no `src/` import is required (SC-001). Templates load through the existing format with **no schema change / no migration**; `schemaVersion` stays `1`; round-trip fidelity preserved.

## 3. Test groups (TDD — written before implementation)

| Group | Covers | Key assertions |
|-------|--------|----------------|
| `jet_report_engine_test` | C1, C2, C3 | bound elements show values (no tokens); detail repeats N×; aggregates correct; pageCount matches |
| `lazy_pagination_test` | C4, C5 | `pageAt(0)` builds without other frames; `pageAt(i)` cached; lazy frame ≡ eager `layout()` frame; PAGE_COUNT correct |
| `render_locale_test` | C7 | en vs de/tr formatting differs correctly; independent of `Intl.defaultLocale` |
| `data_source_parity_test` | C8 | in-memory == JSON == object-backed (incl. nested collection) |
| `render_diagnostics_test` | C9, C10 | each malformed input → specific diagnostic + non-crashing render; URL-only image → placeholder + diagnostic |
| `performance_test` | C4 | 1,000-record first-page within budget; no all-pages materialization |
| `jet_report_preview_test` | C6, C11 | nav bounds; page X of N; fit-to-width; keyboard + accessible names |
| `preview_localization_test` | C11 | en/de/tr chrome + English fallback |
| `goldens/rendered_invoice_test` | C2, C6 | data-filled invoice, paginated, light/dark — shared-pipeline parity |
| `architecture/layer_boundaries_test` (extend) | C12 | new public exports reachable; seam boundaries respected; encapsulation intact |
| `apps/.../rendered_invoice_example_test` | C1–C3, C11; SC-008 | playground example renders + previews end-to-end in < 30 lines of integration |

## 4. Non-goals (explicit — FR-020 / Assumptions)

- No file/document **export** (PDF, image files, print spooling). The `RenderedReport`/`PageFrame` IR is structured so a later export slice consumes it without rework, but no export API ships here.
- No **zoom / interactive editing / annotation / print dialog** in the preview (clarification Q3).
- No **template schema change**, migration, or new heavy runtime dependency.
- No **image I/O** by the library (host pre-resolves bytes).
