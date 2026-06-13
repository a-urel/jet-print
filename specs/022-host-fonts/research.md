# Phase 0 Research: Host & System Fonts in Font Pickers

All decisions are grounded in the current code (file:line) and the spec clarifications
(2026-06-13): host supplies **bytes**, registers **before build**, duplicates resolve
**last-wins**. OS-font discovery is out of scope (spec "Resolved Scope Decision").

---

## §1 — The render chain carries its own registry (the WYSIWYG seam) ★ key decision

**Decision**: The host threads fonts into **two** touch-points only —
`JetReportDesigner.fonts`/`JetReportWorkspace.fonts` (interactive) and
`RenderOptions.fonts` (headless render). `JetReportEngine.render` builds one
`FontRegistry` (`registerDefault()` then host families) and **attaches it to the
`RenderedReport`** it returns. `JetReportPreview`, `JetReportExporter` (`toPdf`/
`pageToPng`), and `JetReportPrinter` **read that registry off the report** instead of each
constructing `FontRegistry()..registerDefault()`.

**Rationale**: Exploration confirmed every render path consumes the same IR —
`RenderedReport` of backend-agnostic `PageFrame`s
([rendered_report.dart](../../packages/jet_print/lib/src/rendering/engine/rendered_report.dart)).
Preview's local registry only *paints* glyphs for frames the engine *already measured*
([jet_report_preview.dart:118-120](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L118-L120));
the exporter
([jet_report_exporter.dart:43,74](../../packages/jet_print/lib/src/rendering/export/jet_report_exporter.dart))
and printer (delegates to the exporter) do the same. If the painting/embedding registry
differs from the layout-measurement registry, glyphs render with bytes other than were
measured — a silent WYSIWYG break (Principle IV, NON-NEGOTIABLE). Carrying the registry on
the report makes the three downstream paths inherit host fonts **for free and unable to
diverge**, and shrinks the "thread through four/five entry points" footgun
([021 plan §Complexity row 2](../021-format-properties/plan.md)) to two host actions.

**Alternatives considered**:
- *A `fonts` parameter on every public entry point (designer, preview, engine, exporter,
  printer)* — the literal "four entry points" reading. Rejected: five threading points the
  host must keep in sync; forgetting one silently breaks export fidelity — exactly the trap
  021 warned about.
- *Expose `FontRegistry` publicly and let the host pass one instance everywhere* —
  rejected: leaks an internal, mutable type into the public surface (Principle I) and still
  needs threading at each call.

---

## §2 — Public font value types: bytes in, no registry exposure

**Decision**: Two value types in the **rendering** layer (new `lib/src/rendering/text/jet_font.dart`):
- `JetFontFace { Uint8List bytes; JetFontWeight weight = JetFontWeight.normal; bool italic = false }`
- `JetFontFamily { String name; List<JetFontFace> faces }`

The host passes `List<JetFontFamily>` (no `JetFontSet` wrapper). `FontRegistry` is **not**
exported.

**Rationale**: Matches the clarified "in-memory bytes" input; `FontRegistry.register`
already takes `(family, Uint8List bytes, {weight, italic})`
([font_registry.dart:28-36](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L28-L36)),
so the value types mirror its existing shape. `JetFontWeight` is the domain enum already
public ([text_style.dart, exported](../../packages/jet_print/lib/jet_print.dart#L87-L88));
reusing it keeps weights consistent with `JetTextStyle`. A bare `List` over a wrapper type
keeps the public surface minimal (Principle I).

**Alternatives considered**: a `JetFontSet` wrapper (one more public type for marginal
ergonomics — rejected); accepting asset paths/`Future`s (rejected per the clarification —
bytes are source-agnostic and keep the library headless, Principle I).

---

## §3 — Validation reuses the existing parser; reject is detectable & synchronous

**Decision**: `JetFontFamily` validates **eagerly in its constructor**: it requires at
least one regular face (`weight == normal && !italic`, FR-001) and parses every face's
bytes through the existing
[`parseTtfMetrics`](../../packages/jet_print/lib/src/rendering/text/ttf/ttf_metrics.dart#L13),
re-throwing its `FontFormatException` with the offending family name. `FontFormatException`
is **re-exported** from the barrel.

**Rationale**: `parseTtfMetrics` already throws `FontFormatException` on empty/too-short/
malformed/missing-table fonts
([ttf_metrics.dart:11-52](../../packages/jet_print/lib/src/rendering/text/ttf/ttf_metrics.dart#L11-L52);
[font_format_exception.dart](../../packages/jet_print/lib/src/rendering/text/font_format_exception.dart)) —
FR-010/SC-006 ("the host can detect a rejection programmatically") is satisfied by simply
surfacing it. Validating **at family construction** (not at registry/widget build) gives
the host a synchronous `try/catch` at the natural point and guarantees nothing throws later
inside `build()` or a headless `render()`. The registry ingest can then assume good bytes.

**Alternatives considered**: lazy validation when the registry is built (rejected — defers
detection into widget construction / a render call, where throwing is hostile); a bespoke
`JetFontException` (rejected — `FontFormatException` is the existing, accurate type).

**Cost**: host bytes parse twice (validation + `register`). Startup-only, host-faces-only;
tracked in plan Complexity. Not optimized away to avoid leaking internal `FontMetrics`.

---

## §4 — Last-wins and stable order hold by construction

**Decision**: `FontRegistry.registerHostFonts(List<JetFontFamily>)` applies families
**after** `registerDefault()`, in list order, calling `register` per face. No new ordering
logic.

**Rationale**: `register` is `_entries[key] = _FontEntry(...)` keyed by
`family|weight|italic`
([font_registry.dart:34-35,131-132](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L34-L35)) —
a later registration of the same face overwrites = **last-registration-wins** (FR-009),
with exactly one entry per face. The
[`families`](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L77-L85)
getter already lists `defaultFamily` first, then keys in insertion order, deduped — so the
picker shows **built-ins first, then host families in the order supplied** (FR-008), stable
across openings. A host name equal to a built-in shadows that family's registered faces but
never removes it: `registerDefault()` ran first, `hasDefault` stays true, and `_resolve`
always ends at the default ([lines 71-72, 118-129](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L118-L129)) —
FR-006 holds. Docs recommend distinct names (tracked in plan Complexity).

---

## §5 — Regular face required; missing variants fall back (no new behavior)

**Decision**: `JetFontFamily` requires a regular face; bold/italic/bold-italic are
optional. A request for a missing variant uses the **existing** fallback chain.

**Rationale**: The clarified/FR-001 minimum is a regular face. `_resolve` already falls
exact → same-family-regular → default
([font_registry.dart:118-129](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L118-L129)),
and `bytesFor` returns the **same instance** for variants resolving to one entry — so a
regular-only host family rendered bold reuses its regular face with no error and embeds
once (FR-005, edge case "Partial faces"). Nothing new is needed.

---

## §6 — Picker, preview-preload, and export embedding are reused unchanged

**Decision**: No new picker, preload, or export code. Once host fonts are in the relevant
registry they appear automatically.

**Rationale**:
- The picker `_FontFamilyRow` reads `fonts.families`, previews each item in its own
  typeface, and flags stored-but-unregistered names
  ([style_editors.dart:344-405](../../packages/jet_print/lib/src/designer/layout/panels/style_editors.dart#L344-L405)) —
  host families flow in via the designer's hoisted registry (FR-002).
- `preloadUiFontFamilies` iterates the registry's families to preload each Regular face
  for picker previews
  ([jet_report_designer.dart:129](../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L129)) —
  host families preload with no change.
- PDF embedding is keyed by the byte instance and embeds once per used face
  ([pdf_painter.dart embedded-fonts cache]); PNG reuses `CanvasPainter`; both pull bytes
  from the carried registry (§1) — FR-003/FR-004 hold with no per-path code. **No new
  dependency** (`pdf` already present).

---

## §7 — No schema change; unavailable-font portability is already built (US2)

**Decision**: `kReportSchemaVersion` stays as-is; no migration. A report naming a font
absent in the session uses the 021 unavailable-family path.

**Rationale**: A text element already persists only a font-family `String`; host fonts add
no field (spec Assumptions; "Out of Scope" — no font bytes in the template). The 021 picker
already preserves an unregistered stored name, marks it unavailable, and renders via the
registry fallback
([style_editors.dart:367-401](../../packages/jet_print/lib/src/designer/layout/panels/style_editors.dart#L367-L401)) —
US2/SC-003 hold for host fonts unchanged. Tests confirm a pre-feature report round-trips
byte-identically (Principle V).

---

## §8 — Playground demonstrates the full thread (FR-012)

**Decision**: The **playground** (not the library) bundles one custom `.ttf`, builds a
`List<JetFontFamily>` from its bytes, and passes the **same list** to
`JetReportWorkspace.fonts` and to the `renderReport` callback's `RenderOptions.fonts`.

**Rationale**: The playground currently constructs `JetReportWorkspace` with no fonts
([apps/jet_print_playground/lib/main.dart](../../apps/jet_print_playground/lib/main.dart));
FR-012 requires the sample app to register a custom font and show it end-to-end. Keeping the
font asset in the playground (not `packages/jet_print`) preserves library
self-containment (Principle I) and models exactly what a real host does. The shared-list
pattern is the documented mitigation for the two-threading-points item (§1).
