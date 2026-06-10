# Quickstart — Render a designed report to an on-screen preview

**Audience**: a host developer who has a designed `ReportTemplate` and some data, and wants a paginated, data-filled preview. Everything imports from the single entry point — no `src/` access (SC-001). The full integration fits in **under 30 lines** (SC-008).

```dart
import 'package:flutter/material.dart';
import 'package:jet_print/jet_print.dart';

// 1. The data: one invoice with a nested collection of line items.
//    (Use JetJsonDataSource for a JSON payload, or JetObjectDataSource<T>
//     for your own domain objects — identical output, SC-006.)
final source = JetInMemoryDataSource([
  {
    'invoiceNo': 'INV-1042',
    'customer': 'Acme GmbH',
    'lines': [ // nested collection → master/detail
      {'desc': 'Widget',  'qty': 3, 'price': 4.50},
      {'desc': 'Gadget',  'qty': 1, 'price': 12.00},
    ],
  },
]);

// 2. Render: template + data + per-render options (parameters + explicit locale).
final RenderedReport report = const JetReportEngine().render(
  template,                       // a ReportTemplate from the data-aware designer (009)
  source,
  options: const RenderOptions(
    parameters: {'printedBy': 'A. Urel'}, // $P{printedBy}
    locale: Locale('de'),                 // FR-012a — formatting locale, not the UI locale
  ),
);

// 3. Preview: a read-only paginated viewer (prev/next, "page X of N", fit-to-width).
//    The first page renders without materializing the rest (FR-021).
final Widget preview = JetReportPreview(report: report);

// 4. Optional: inspect diagnostics (unknown field, missing param, unresolved image, …).
for (final Diagnostic d in report.diagnostics.entries) {
  debugPrint('[${d.severity.name}] ${d.message}'
      '${d.elementId == null ? '' : ' @${d.elementId}'}');
}
```

## What you get

- **Values, not tokens** — every `$F{}`/`$P{}`/`$V{}` binding shows its evaluated value; the invoice total equals the sum of line amounts; line items each appear once (SC-002).
- **Paginated** — content splits at band boundaries; page header/footer repeat; "page X of N" reflects the real count (SC-005).
- **WYSIWYG** — the preview is visually identical to the designer's surface for the same template (same paint pipeline; SC-003).
- **Robust** — malformed inputs produce specific diagnostics and a non-crashing, best-effort render (SC-007).

## Choosing a data source

| You have… | Use | Notes |
|-----------|-----|-------|
| In-memory rows (`List<Map>`) | `JetInMemoryDataSource(rows)` | Optional explicit `FieldDef` schema; otherwise inferred. |
| A JSON payload | `JetJsonDataSource(jsonString)` | Array-of-objects; delegates to in-memory. |
| Your own domain objects | `JetObjectDataSource<T>(items, schema, extract)` | Lazy per-row field extraction. |

All three produce identical output for the same logical dataset (SC-006). Nested collections (master/detail) are a `collection` `FieldDef` carrying child rows.

## Constraints to know

- **Images**: supply image **bytes** through the data source (or embed them). A URL-only image renders a placeholder + emits a diagnostic — the library does no network/disk I/O (FR-012b/FR-015).
- **Locale**: formatting follows `RenderOptions.locale`, *not* your app's UI locale (FR-012a). The preview's chrome (page indicator, nav) is separately localized en/de/tr with English fallback.
- **Export is not in this slice**: this is on-screen preview only. PDF/image/print arrive in a later slice; the `RenderedReport` is structured so that slice consumes it without rework (FR-020).

## Verify it end-to-end

The playground ships a runnable **rendered-invoice** example (`apps/jet_print_playground/lib/rendered_invoice_example.dart`): build the invoice data source, render the bound invoice template, and open `JetReportPreview`. Run the app and open the Preview path, or run `flutter test apps/jet_print_playground` (from the repo root) to drive the example headlessly.
