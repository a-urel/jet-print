# Quickstart: Register a host font end-to-end (spec 022)

Goal: make a custom font ("Acme Brand") selectable in every designer picker and render it
**identically** on canvas, preview, PDF, and PNG — then see it degrade gracefully where it
isn't registered. Mirrors User Stories 1–2 and the playground demo (FR-012).

---

## 1. Build the font once, before showing anything

A face is **bytes** the host loads (asset, file, network — your choice). Validation is
synchronous, so you find a bad font immediately:

```dart
import 'package:jet_print/jet_print.dart';

Future<List<JetFontFamily>> loadBrandFonts() async {
  final Uint8List regular = await loadBytes('assets/fonts/AcmeBrand-Regular.ttf');
  final Uint8List bold    = await loadBytes('assets/fonts/AcmeBrand-Bold.ttf');
  try {
    return <JetFontFamily>[
      JetFontFamily(
        name: 'Acme Brand',
        faces: <JetFontFace>[
          JetFontFace(bytes: regular),                              // required regular
          JetFontFace(bytes: bold, weight: JetFontWeight.bold),     // optional
        ],
      ),
    ];
  } on FontFormatException catch (e) {
    // FR-010 / SC-006 — a malformed/empty face is rejected here, detectably.
    log('Skipping brand font: $e');
    return const <JetFontFamily>[];
  }
}
```

A family needs **at least a regular face**; missing bold/italic fall back automatically
(FR-005). The same name registered twice → **last one wins** (FR-009).

## 2. Thread the SAME list into the two touch-points

Host fonts reach the picker/canvas via the **designer**, and the preview/export/print chain
via **`RenderOptions`**. Pass one shared list to both:

```dart
final List<JetFontFamily> fonts = await loadBrandFonts();

JetReportWorkspace(
  controller: controller,
  dataSchema: schema,
  fonts: fonts,                                   // ← picker + canvas (US1)
  renderReport: (ReportTemplate t) => const JetReportEngine().render(
    t,
    dataSource,
    options: RenderOptions(fonts: fonts),         // ← preview + export + print
  ),
  onExportPdf: (RenderedReport r) => save(await const JetReportExporter().toPdf(r)),
  onPrint: (RenderedReport r) => const JetReportPrinter().printReport(r),
);
```

That's the whole integration. **`JetReportPreview`, `JetReportExporter`, and
`JetReportPrinter` take no font argument** — the `RenderedReport` the engine returns carries
its font registry, so they render exactly what was measured (WYSIWYG by construction —
Principle IV).

> Using the designer alone? `JetReportDesigner(fonts: fonts, …)` — same parameter.

## 3. What you observe

1. Open a text element's **Family** picker → "Acme Brand" appears after the built-ins
   (JetSans/JetSerif/JetMono), previewed in its own typeface (FR-002, FR-008).
2. Apply it → the canvas re-renders in Acme Brand immediately; the choice persists on save.
3. Preview, **Export PDF**, and **Export PNG** → the text is Acme Brand in all of them,
   pixel-for-pixel matching the canvas; the PDF text stays selectable/searchable and embeds
   the face once (FR-003, FR-004, SC-002).
4. Register **nothing** → the designer behaves exactly as before, built-ins only (SC-005).

## 4. Portability when the font is absent (User Story 2)

Open an Acme-Brand report in a session that did **not** register it (another machine, a
viewer, a shared template):

- It opens with **zero errors**; text renders in the fallback font.
- The picker shows `Acme Brand (unavailable)`; the stored name is **preserved** on save
  (never silently swapped) — SC-003.
- Export still succeeds using the fallback.

Re-register "Acme Brand" in that session and reopen → it renders in the real font again.
Template files carry the font **name**, not its bytes (exported PDFs are self-contained).

## 5. Verify

```bash
flutter test packages/jet_print        # unit + widget + golden + PDF parity (C1–C12)
flutter analyze                        # zero warnings
dart format --output none --set-exit-if-changed packages/jet_print
```

The cross-path parity golden (C9) and the PDF-embedding test (C12) are the guardrails that
keep design == preview == PDF == PNG for host fonts.
