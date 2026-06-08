# Spec 008b — Group-aware pagination (`reprintHeaderOnEachPage` + `keepTogether`)

**Status:** design approved (forks settled; three pre-write review rounds folded in, §12).
**Depends on:** 008a layout engine + 007c grouping, both merged to `main`. Reuses the 008a
`BandMeasurer`/`ReportLayouter` and the 007c group bands; the 005b `VariableCalculator` is untouched.
**Layer:** `domain/` (+2 `ReportGroup` flags) · `rendering/fill/` (+1 internal IR field) ·
`rendering/layout/` (the algorithm). No expression engine enters layout (008a invariant preserved).

---

## §1 — Purpose & scope

008b makes grouped reports paginate correctly across page breaks, via two **independent, opt-in**
`ReportGroup` flags (both default `false`):

- **`reprintHeaderOnEachPage`** — when a group spans a page break, repeat its group header band(s)
  at the top of the new page (outer→inner), so a continued group keeps its heading.
- **`keepTogether`** — try to keep a whole group on one page: if it doesn't fit in the remaining
  space but *does* fit on a fresh page, move it there before splitting.

The two compose without special-casing: `keepTogether` *reduces* the breaks that split a group;
`reprintHeaderOnEachPage` *handles* the breaks that remain (a group too tall to keep together, or
`keepTogether` off).

**In scope:** the two flags, the IR completion that carries group identity into layout, the
group-instance lifetime model, and the layouter changes (pre-measure + keep-together break +
header re-emit).

**Out of scope (separate later specs):** group footer reprint, `background` band, `startNewPage`
(title-on-own-page), multi-column flow, `printWhen` (a Fill concern), page-scoped substitution
(008c). Both flags have **defined behavior only for groups with ≥1 group-header band** (§5); they are
no-ops (with an info diagnostic) on a header-less group.

## §2 — Architecture & the input split

008b extends the 008a pure function `(ReportTemplate, FilledReport) → LayoutResult`. The flags are
read from `template.groups`; group identity per band is read from a new internal-IR field
`FilledBand.group`. Layout stays headless and deterministic (same inputs → identical
`List<PageFrame>` + diagnostics, compared as in 008a). The 007c Fill pass is unchanged except for a
one-line propagation of the already-existing `ReportBand.group` into the resolved `FilledBand`.

## §3 — Data model

### §3.1 — `ReportGroup` gains two opt-in flags (domain + serialization)

```dart
class ReportGroup {
  const ReportGroup({
    required this.name,
    required this.expression,
    this.keepTogether = false,            // NEW
    this.reprintHeaderOnEachPage = false, // NEW
  });
  // ...
  final bool keepTogether;
  final bool reprintHeaderOnEachPage;
}
```

- **Serialization** lives on `ReportGroup.toJson`/`fromJson` (which `report_codec` already delegates
  to). Additive and **omitted when false**; decoded as `json['<flag>'] as bool? ?? false`. So an old
  template with neither key loads with both `false` — backward compatible.
- `==`/`hashCode`/`toString` are updated to include both flags.

### §3.2 — `FilledBand` gains group identity (internal IR)

```dart
class FilledBand {
  FilledBand({
    required this.type,
    required this.height,
    required List<ReportElement> elements,
    required Map<String, JetValue> variables,
    this.group,                            // NEW — the ReportGroup.name for group bands; null otherwise
  }) : /* ...existing frozen-collection init... */;
  // ...
  final String? group;
}
```

- Populated by Fill's `addBand`, which already holds the source `ReportBand`: a one-line
  `group: band.group`. `ReportBand.group` exists since 007c.
- `FilledBand` is the **internal Fill→Layout IR — it has no `toJson`/`fromJson`** and never persists,
  so this carries **zero schema/serialization impact**. It completes the IR that 007c left
  "intentionally incomplete."
- `==`/`hashCode`/`toString` are updated to include `group`.

## §4 — Schema-versioning decision (explicit pre-1.0 exception)

Adding the two persisted `ReportGroup` flags **is a schema change**, and the codec's own contract is
unambiguous: *"Bump on every schema change and ship a [SchemaMigration] for the previous version"*
(`report_codec.dart`). 008b consciously **does not** bump `kReportSchemaVersion` (stays `1`). This is
recorded as an **explicit exception to that contract**, not a claim that it complies:

- **Constitution V's hard requirement is *backward* compatibility** ("older serialized reports MUST
  continue to load in newer library versions"). The flags are additive optional fields defaulting to
  `false`, so an older template loads unchanged — backward compat is satisfied.
- What the no-bump consciously **trades away** is *forward* compatibility: a new template's flags
  would be silently dropped by a hypothetical older build. Pre-release, no such build exists, so the
  tradeoff costs nothing now.
- This continues the standing pre-1.0 decision applied to 007b's `TextElement.expression` and 007c's
  `ReportBand.group` (both added at schema 1). A dedicated schema-versioning pass before 1.0 will
  settle the bump/migration policy across all accumulated additive fields at once.

(If the project later elects to pay the versioning debt, the migration is trivial — the v1→v2
migration is the identity, since every v1 template is a valid v2 template with both flags `false`.)

## §5 — The group-instance lifetime model

Both features need to know, at any point in the flat `FilledReport` stream, **which group instances
are currently open** (header-repeat re-emits their headers; keep-together measures their extent).
Because Fill emits headers and footers *independently* (a group may have headers only, footers only,
both, or neither — 007c `GroupBandIndex`), the lifetime cannot be driven by footers alone. It is
driven by **headers + nesting level**, with footers and report bands closing instances.

`level[g]` = the index of `g` in `template.groups` (outermost = 0). The open set is a stack ordered
outer→inner (strictly increasing level, because groups always open outermost-first).

### §5.1 — Open / reopen

Track `prevHeaderGroup` = the group name if the immediately preceding band was a `groupHeader`, else
`null`. On a `groupHeader(g)`:

- **Continuation** (`prevHeaderGroup == g`): another header band of the *same* instance (007c allows
  multiple header bands per group). Append it to `g`'s current open entry.
- **New instance** (otherwise): pop every open group with `level ≥ level[g]` (this closes a prior
  instance of `g` and any still-open inner groups), then push `g` with its first header band, its
  level, and its `reprintHeaderOnEachPage` flag.

The `prevHeaderGroup` test is essential: at a break the prior instance is still on the stack, so a
re-opening `groupHeader(g)` after a footer/detail must be treated as a *new* instance, while a
contiguous second header band of one instance must be treated as a *continuation*.

### §5.2 — Close (three triggers; earliest wins)

1. **Footer-run end (cascade).** After the last `groupFooter(g)` of a contiguous run (the next band
   is not `groupFooter(g)`), pop every open group with `level ≥ level[g]`. The cascade closes `g`
   and any still-open inner group — e.g. a header-only inner group with no footer of its own, ended
   by its outer group's footer.
2. **A `summary` or `noData` band.** Pop **all** open groups before processing the band. This covers
   the all-header-only report, where no footer ever fires, so a break before `summary` cannot reprint
   a group header above it.
3. **Next-instance / outer header.** Already handled by §5.1's new-instance pop.

### §5.3 — One documented, accepted edge

A header-only *inner* group can still have its header reprinted above its *outer* group's footer, if
a page break lands in the narrow window between that group's last detail and the outer footer. It is
cosmetic (the inner label sits above the outer total) and rare; 008b accepts it rather than add a
fourth closure rule. Footer-having groups and the common cases are exact.

## §6 — `keepTogether`

### §6.1 — Pre-measure + extent pre-pass

Layout first measures **every** body band once (`measured[i] = bandMeasurer.measure(filled.bands[i])`)
— pure and position-independent, so lookahead is free. Then, for each **new-instance** opening header
of a `keepTogether` group at index `o` (level `L`), it computes the instance **extent** = the sum of
`measured[k].height` from `k = o` up to (but excluding) the first band that **exits** `g`:

> A band at `k > o` **exits** `g` when it is a new-instance `groupHeader` at `level ≤ L`, a
> `groupFooter` at `level < L` (an *outer* group's footer ending the block), a `summary`, or a
> `noData`; end-of-stream also ends it.

So `g`'s own footers (`level == L`) and all inner bands (`level > L`) are **included**; an outer
footer is **excluded**. A footer-having group's extent includes its footer; a header-only group's
extent stops before the outer footer — exact for both shapes (the over-count the pure header-driven
rule would have caused is avoided).

### §6.2 — Break decision (a real promise, one break per band)

When the pagination loop reaches a `keepTogether` group's opening header at `o`, the open stack holds
`g`'s **outer** groups (g not pushed yet). The headers that will actually repeat on a fresh page are
those outer groups with `reprintHeaderOnEachPage`:

```
repeatedOuter = Σ (Σ height of its header bands) for open groups with reprint == true
fresh         = bodyCapacity - repeatedOuter
keepBreak fires iff:  extent <= fresh  AND  cursorY + extent > bodyBottom  AND  cursorY > bodyTop
```

On a `keepBreak`, the whole group provably fits on the fresh page: `repeatedOuter + extent ≤
bodyCapacity`, so no band inside the group triggers a later break. If `extent > fresh`, **no** forced
break — the group flows and may split, and `reprintHeaderOnEachPage` (if set) covers the split. The
promise is therefore precise: *a `keepTogether` group stays whole whenever it fits a fresh page after
the repeated outer headers; otherwise it splits.*

`keepBreak` and the standard 008a overflow break are **mutually exclusive** for one band (a `broke`
flag), so a single band triggers at most one page break — no re-break, no blank header-only page.

## §7 — `reprintHeaderOnEachPage`

On **any** page break while a flagged group is open (whether from `keepBreak`, the 008a overflow
break, or — later — any other break), the layouter re-emits the open groups' header bands at the top
of the new page, before placing the triggering band:

```
breakPage():
  pages.add(FrameBuilder(page)); cursorY = bodyTop
  for o in openStack (outer→inner) where o.reprint:
     for hmb in o.headers: place(hmb.elements, cursorY, pages.last); cursorY += hmb.height
```

- The re-emitted header is the **same resolved instance** already measured/placed at the group's
  open — the group key and variable snapshot are unchanged on a continuation page, so the content is
  identical (no re-resolution, no expression engine).
- Order is outer→inner "for free": 007c guarantees headers stream outermost-first, so the open stack
  is already in that order.
- A flag on a header-less group is a no-op (nothing to re-emit) + an info diagnostic (§9).

## §8 — Components & files

**Modify (domain + serialization):**
- `lib/src/domain/report_group.dart` — `keepTogether`, `reprintHeaderOnEachPage` (fields, ctor,
  `fromJson`/`toJson` additive omit-when-false, `==`/`hashCode`/`toString`).

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/filled_report.dart` — `FilledBand.group` (field, ctor, `==`/`hashCode`/
  `toString`).
- `lib/src/rendering/fill/report_filler.dart` — `addBand` passes `band.group` into `FilledBand` (one
  line).

**Modify (`rendering/layout/`):**
- `lib/src/rendering/layout/report_layouter.dart` — pre-measure all bands; the group-span extent
  pre-pass; the open-group lifetime stack (§5); the keep-together break (§6) and header re-emit (§7)
  in the pagination loop. No new file; the body loop grows (consistent with the single-method idiom).

**No change:** `band_measurer.dart` (reused as-is), `report_codec.dart` (delegates to
`ReportGroup.toJson`/`fromJson`), the 005b `VariableCalculator`, the 007c `GroupBandIndex`.

## §9 — Diagnostics & edges (render-don't-crash; reuses `ReportDiagnostics`)

| Condition | Severity | Behavior |
|---|---|---|
| `keepTogether`/`reprintHeaderOnEachPage` set on a group with **no header band** | **info** | flag is a no-op for that group; report still renders |
| A `keepTogether` group's extent **> bodyCapacity** (can't fit any page) | (none) | no forced break; group flows and may split (header-repeat covers it if flagged) |
| Re-emitted headers + the triggering band overflow the new page | (none, 008a behavior) | atomic placement, overflow, no re-break (no infinite loop) |
| Header-only inner group header reprinted above an outer footer (§5.3) | (none) | accepted cosmetic edge |

No new fatal/structural error: 008b adds no parse paths; malformed templates already fail at
decode/fill. All 008a diagnostics (overcommit, unresolved chrome, ignored bands, page mismatch) carry
over unchanged.

## §10 — Testing (TDD; `PageFrame` data goldens — geometry/coords/page-counts, **not** image goldens)

**Domain — `report_group_test.dart` (extend):**
- Both flags default `false`; round-trip when `true`; **omitted from JSON when `false`**; decoded as
  `false` when absent.
- Both flags participate in `==`/`hashCode` (groups differing only in a flag are unequal).

**IR — `filled_report_test.dart` (extend):**
- `FilledBand.group` participates in `==`/`hashCode` (two bands differing only in `group` are
  unequal; equal when identical); `toString` unaffected structurally.

**Fill — `report_filler_test.dart` (extend):**
- A `groupHeader`/`groupFooter` `FilledBand` carries its `group` name; non-group bands carry `null`.

**Layout — `report_layouter_test.dart` (extend, `PageFrame` goldens):**
- **reprint, single group:** a group spanning two pages reprints its header at `bodyTop` of page 2
  (assert the header primitive's page-2 coordinates); **off** by default (no reprint when the flag is
  unset).
- **reprint, nested:** an inner+outer group spanning a break reprints **outer→inner** at page 2 top.
- **reprint multi-header:** a group with two header bands reprints **both**, stacked in authored order.
- **Break between an inner footer and an outer footer** → only the **outer** header reprints (the
  inner group already closed at its footer-run end). *(must-have, R3)*
- **Break between the final group footer and `summary`** → **no** header reprints above summary.
  *(must-have, R3)*
- **Header-only group** with reprint: closes on the next same-or-outer header / `summary`; reprints
  while open, not after it ends.
- **keepTogether fits fresh page:** a group that doesn't fit the remainder but fits a fresh page is
  moved whole (one page break before its header; the group is unsplit; assert page count + that the
  group's bands all land on one page).
- **keepTogether too tall:** a group taller than `bodyCapacity` is **not** force-broken; it splits
  (and reprints if flagged).
- **keepTogether accounts for repeated outer headers:** a nested case where the inner group fits
  `bodyCapacity` but **not** `bodyCapacity − repeatedOuter` splits rather than being declared "fits."
- **one break per band:** a `keepTogether` opening header does not produce a blank page (the
  keep-break and overflow break don't both fire).
- **determinism:** two runs equal (frames by value; diagnostics by the 008a normalized projection of
  `(severity, message, elementId)` tuples).
- **header-less flagged group:** an **info** diagnostic; layout otherwise identical to flags-off.

**Regression:** all 008a `report_layouter_test`, 007c `report_filler_test`, and existing
`report_group`/`filled_report` tests stay green (flags-off path is byte-identical to 008a).

**Architecture:** the existing `layout/` seam test (no `expression/`, headless) still passes — 008b
adds no expression import.

## §11 — Design decisions

1. **Two independent opt-in flags** (`keepTogether`, `reprintHeaderOnEachPage`), both default
   `false` — JasperReports parity; maximum author control; each is a no-op until enabled per group.
2. **`FilledBand.group` is the minimal IR completion** — the one thing the flat stream lacks is
   *which group a band belongs to*; adding it to the internal IR (not the persisted template) is
   enough for both features and costs no schema change.
3. **Header-driven hybrid lifetime** (§5) — footers are independently optional, so closure cannot be
   footer-only; opening is header-driven, closure is footer-run-end (cascade) + `summary`/`noData` +
   next-instance. This is the model that survives header-only, footer-only, multi-header, and
   multi-footer groups (the three review rounds that hardened it, §12).
4. **Flags require ≥1 header band** — both anchor on the header (extent measured from it; reprint
   re-emits it). Header-less groups are no-ops + info, sidestepping the footer-only ambiguity.
5. **`keepTogether` is a precise promise, not best-effort** — the fit check subtracts the headers
   that will actually repeat on the fresh page (`bodyCapacity − repeatedOuter`), so a group declared
   "fits" provably does (§6.2). One break per band via the `broke` guard.
6. **Reprint re-emits the already-resolved header instance** — same group key/snapshot on a
   continuation page, so no re-resolution and no expression engine in layout (008a invariant kept).
7. **Conscious pre-1.0 schema exception** (§4) — no `kReportSchemaVersion` bump for the two additive
   flags; backward compat is met, the forward tradeoff is accepted, deferred to a pre-1.0 versioning
   pass. Documented as a deviation from the codec contract, not as compliance.

## §12 — Review history

**R1 (data model), folded in:**
1. *Schema "no bump" framed as if it matched the rule (High).* The codec says bump on every schema
   change; adding persisted `ReportGroup` fields is a schema change. **Verified and reframed:** §4 now
   documents the no-bump as an **explicit conscious pre-1.0 exception** (backward compat met, forward
   tradeoff accepted), mirroring 007c — not as compliance. The bump-now alternative was offered and
   declined in favor of the standing precedent.
2. *Undercounted test surface (Medium).* `FilledBand` and `ReportGroup` are value types with existing
   `==`/JSON tests. **Folded in:** §10 extends `filled_report_test` (FilledBand.group equality) and
   `report_group_test` (flag round-trip + equality), not only filler/layouter coverage.
3. *"Goldens" ambiguous (open).* **Clarified:** `PageFrame` data/geometry goldens (coords, page
   counts), like 008a — not image goldens (§10).

**R2 (lifetime), folded in:**
1. *Footer-driven lifetime broken (High).* "Close on footer-run end / pop on first footer"
   mis-models header-only groups (never close) and multi-footer groups (close inconsistently);
   header-only templates are already valid (`GroupBandIndex` headers/footers independent;
   `report_filler_test` header-only case). **Verified and replaced:** the lifetime became
   **header-driven** with a `prevHeaderGroup` continuation test and level-aware new-instance pops
   (§5.1).

**R3 (footer-boundary leak), folded in:**
1. *Pure header-driven still leaks across footer boundaries (High).* Inner footers precede outer
   footers, and all footers precede `summary`; under pure header-driven, an inner group stayed open
   past its own footer, so a break between inner and outer footers (or before `summary`) reprinted a
   stale header, and the pre-pass extent absorbed the outer footer. **Verified
   (`report_filler.dart`/`report_filler_test.dart`) and fixed:** closure became the **hybrid** of §5.2
   — footer-run-end **cascade** pop (`level ≥ level[g]`) + `summary`/`noData` pop-all + next-instance
   pop — and the extent uses the matching **exit rule** (§6.1) that excludes outer footers. Added the
   two must-have tests (inner↔outer footer break; final footer↔summary break) to §10. The R2 break
   fixes (the `broke` guard, repeated-outer-header fit) were confirmed correct and retained.
