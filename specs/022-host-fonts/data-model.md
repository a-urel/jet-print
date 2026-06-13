# Phase 1 Data Model: Host & System Fonts

No domain/report-model entity changes and **no schema change** — a text element already
stores only a font-family `String`. The "data" here is the new public *input* types, the
internal registry ingest, and where the registry travels. References are file:line in
`packages/jet_print`.

---

## 1. `JetFontFace` — public value type (NEW, rendering layer)

`lib/src/rendering/text/jet_font.dart`

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `bytes` | `Uint8List` | — (required) | The face's raw TTF/OTF bytes (host-sourced). |
| `weight` | `JetFontWeight` | `JetFontWeight.normal` | Reuses the public domain enum ([text_style.dart](../../packages/jet_print/lib/jet_print.dart#L87)). |
| `italic` | `bool` | `false` | |

- `const`-friendly constructor (no eager parse here — validation lives on the family, so a
  face is a plain descriptor; the family is the unit a host registers).
- Value equality (`==`/`hashCode`) over `(identityOf bytes, weight, italic)` — bytes compared
  by identity (large buffers; hosts reuse instances). Dartdoc states this.

## 2. `JetFontFamily` — public value type with eager validation (NEW)

`lib/src/rendering/text/jet_font.dart`

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | Display name shown in pickers and stored in reports (e.g. `"Acme Brand"`). |
| `faces` | `List<JetFontFace>` | At least one **regular** face (`weight==normal && !italic`). |

**Validation (in the constructor — throws synchronously):**
1. `name` non-empty (else `ArgumentError`).
2. `faces` contains ≥1 regular face (else `FontFormatException('… "$name" … needs a regular face')`) — FR-001.
3. Each face's `bytes` parse via `parseTtfMetrics(bytes)`
   ([ttf_metrics.dart:13](../../packages/jet_print/lib/src/rendering/text/ttf/ttf_metrics.dart#L13));
   on `FontFormatException`, re-throw with the family `name` and the face's weight/italic in
   the message — FR-010 / SC-006 (host detects rejection via `try/catch`).
4. No duplicate `(weight, italic)` within one family's `faces` (else `ArgumentError`) — keeps
   a family's faces unambiguous (cross-family/duplicate-name dedup is last-wins at the
   registry, §4 research / FR-009).

Validation is **eager and synchronous** so a host catches a bad font when assembling it,
and neither widget `build()` nor `render()` can throw later.

## 3. `FontFormatException` — now PUBLIC (re-export)

`lib/src/rendering/text/font_format_exception.dart` (unchanged) → add to
`lib/jet_print.dart`. `{ String message; toString() }`. The single detectable rejection
type (SC-006).

## 4. `FontRegistry.registerHostFonts` — internal ingest (CHANGE)

`lib/src/rendering/text/font_registry.dart` (stays internal)

```text
void registerHostFonts(List<JetFontFamily> families) {
  for (final family in families)          // list order = registration order (FR-008)
    for (final face in family.faces)
      register(family.name, face.bytes, weight: face.weight, italic: face.italic);
}
```

- Always called **after** `registerDefault()`, so built-ins exist first and host faces
  overwrite per `family|weight|italic` key = **last-wins** (FR-009), additive (FR-006).
- Re-parses bytes (as `register` does for built-ins). The eager family validation (§2)
  guarantees these calls cannot throw.
- `families` getter unchanged — already yields default-first, then insertion order, deduped
  (FR-008) ([font_registry.dart:77-85](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L77-L85)).

## 5. `RenderOptions.fonts` — host fonts for the render chain (CHANGE)

`lib/src/rendering/engine/render_options.dart`

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `fonts` | `List<JetFontFamily>` | `const <JetFontFamily>[]` | Register-before-render; empty ⇒ today's behavior exactly (SC-005). |

## 6. `RenderedReport` carries the registry — internal (CHANGE) ★ WYSIWYG seam

`lib/src/rendering/engine/rendered_report.dart`

- Add an **internal** `final FontRegistry fonts;` set by the engine when it constructs the
  report (not exported; constructor param is internal).
- `JetReportEngine.render` builds it once:
  `FontRegistry()..registerDefault()..registerHostFonts(options.fonts)`, passes it to
  `ReportLayouter` for measurement **and** stores it on the returned `RenderedReport`
  ([jet_report_engine.dart:56-93](../../packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart#L56-L93)).

## 7. Threading map — who builds vs. reads the registry

| Public entry point | Today | After 022 |
|--------------------|-------|-----------|
| `JetReportDesigner` / `JetReportWorkspace` | builds `FontRegistry()..registerDefault()` ([designer:115](../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L115)) | **+ `fonts` param** → `..registerHostFonts(fonts)`; workspace forwards to designer |
| `JetReportEngine.render` | layout builds a default-only registry internally | builds default+host once; passes to layout **and** carries on `RenderedReport` |
| `JetReportPreview` | builds default-only `_fonts` ([preview:120](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L120)) | **reads `report.fonts`** (no param) |
| `JetReportExporter.toPdf` / `.pageToPng` | builds default-only ([exporter:43,74](../../packages/jet_print/lib/src/rendering/export/jet_report_exporter.dart)) | **reads `report.fonts`** (no param) |
| `JetReportPrinter.printReport` | delegates to exporter | inherits via exporter (no change) |

Host touch-points: **`*.fonts` (designer/workspace)** and **`RenderOptions.fonts`**. The
render chain (engine→report→preview/export/print) carries its registry → WYSIWYG by
construction (Principle IV).

## 8. State transitions (a host font's lifecycle)

```
host bytes ──JetFontFace──▶ JetFontFamily(validate) ──┬─▶ designer.fonts ─▶ hoisted registry ─▶ picker + canvas + preload
   (invalid ⇒ FontFormatException, caught by host)     └─▶ RenderOptions.fonts ─▶ engine ─▶ RenderedReport.fonts ─▶ preview / PDF / PNG / print
```
- **Applied** (name in the active registry): listed in picker, previewed in own typeface,
  measured + painted + embedded from its bytes everywhere.
- **Unavailable** (report names it, not registered this session): 021 path — name preserved,
  marked unavailable in picker, rendered via fallback, re-saved intact (US2 / SC-003). No new
  code.

## 9. No schema change (Principle V)

`kReportSchemaVersion` unchanged; no migration. Text elements persist the family **name**
only (existing). A pre-feature report and a host-font report both round-trip
byte-identically; an unregistered name follows §8 Unavailable. (Template files never embed
font bytes — spec "Out of Scope"; exported PDFs embed used faces, existing behavior.)
