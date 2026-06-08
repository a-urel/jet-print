# Spec 007c — Grouping (group header/footer bands + group-scoped subtotals in the Fill stream)

**Status:** design approved (forks settled; one pre-write review round folded in, §12).
**Depends on:** 007b Fill (flat), merged to `main`. Reuses the 005b `VariableCalculator` grouping
computation **unchanged**.
**Layer:** `rendering/fill/` (the same headless seam as 007b — domain/data/expression only).

---

## §1 — Purpose & the 008 contract

007c completes the Fill data pass for **grouped** reports: it emits `groupHeader`/`groupFooter`
band instances into the `FilledReport` stream at the right break points, with group-scoped
subtotals frozen per band. The 008 (Layout) contract is unchanged from 007b: Layout consumes
**both** the `ReportTemplate` (page chrome, page format) **and** the `FilledReport` (the resolved,
ordered band stream + frozen variable snapshots). A `FilledBand` of type `groupHeader`/`groupFooter`
flows through the existing stream exactly like `title`/`detail`/`summary`/`noData` — Layout lays
bands out in stream order and does not need to know a band's group identity, so **the IR is not
extended** (no `FilledBand.group`). This matches the existing fill design's statement that Layout
consumes the template and the filled stream together.

## §2 — Scope

**In scope:**
- A `ReportBand`→`ReportGroup` link (one optional field on `ReportBand`).
- `groupHeader` emission at each group's start; `groupFooter` emission at each group's end.
- Correct **group-scoped subtotals** in footers (the value as of the group's last row, *before* the
  breaking row resets it).
- Correct **nesting order** for headers and footers across multiple groups.
- Validation diagnostics for malformed group-band references and duplicate group names.

**Out of scope (later specs):**
- Pagination, page/column chrome bands (`pageHeader`/`pageFooter`/`columnHeader`/`columnFooter`/
  `background`), repeating a group header after a page break, "keep-together"/orphan control — all
  **008 (Layout)**.
- Any change to the 005b `VariableCalculator` (its grouping computation is reused as-is).

**Reused from 005b (no change):** the calculator already evaluates group keys per row, detects the
outermost broken group (an outer break **cascades** to all inner groups), resets group-scoped
variables on break, and exposes `brokenGroups` (the set of group names that broke on the most recent
`advance`). 007c is therefore a **driver-only** feature plus one small domain field.

## §3 — The `ReportBand`→`ReportGroup` link

Group bands live in the flat `template.bands` list (like every other band) and are tagged with the
name of the group they belong to:

```dart
class ReportBand {
  const ReportBand({
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
    this.group,                 // NEW — the ReportGroup.name this band belongs to
  });
  // ...
  final String? group;
}
```

- `group` is **meaningful only** for `groupHeader`/`groupFooter` bands. It is ignored on every other
  band type (a stray `group` on a `detail` band is harmless and silently ignored).
- This mirrors the existing name-based link `ReportVariable.resetGroup` (a group is referenced by
  name, never by index).

**Serialization (schema unchanged — see §10 for the rationale):** the codec round-trips `group` as
an **optional, additive** field, omitted when null — identical in shape to how 007b added
`TextElement.expression`:

```dart
// encode
if (band.group != null) 'group': band.group,
// decode
group: json['group'] as String?,
```

## §4 — Group-name uniqueness (invariant + validation)

`ReportGroup.name` **must be unique** within a template. This is already an implicit invariant of
005b — the calculator keys `brokenGroups` as a `Set<String>` and matches `ReportVariable.resetGroup`
by name, so duplicate names make break detection, variable resets, and (now) band routing
ambiguous. 007c makes the invariant **explicit** and **validates** it: at the start of the fill,
duplicate `template.groups` names produce an **error diagnostic** (`Duplicate group name "<name>"`)
and the data pass continues (render-don't-crash; the calculator's behavior under duplicates is
defined-but-meaningless, and the diagnostic makes the misconfiguration explicit).

## §5 — The emission algorithm

The driver keeps two pieces of state across the row loop, in addition to the band accumulator:
- `prevValues` — the `calc.values` snapshot captured **after the previous detail row** (the ended
  group's subtotal *before* the breaking row's reset overwrites it).
- `prevRow` — the previous data row (the last row of a just-ended group).

Per `advance(row)`, the driver reads `calc.brokenGroups` and acts:

1. **First data row** (`prevRow == null`): emit **all** group headers, **outermost→innermost**, then
   the `detail`.
2. **A break** (`brokenGroups` non-empty): **before** the new `detail` —
   a. emit footers for the broken groups, **innermost→outermost**, then
   b. emit headers for the broken groups, **outermost→innermost**, then
   c. emit the `detail`.
3. **No break:** just the `detail`.
4. **After the last row:** emit footers for **all** groups, **innermost→outermost**, then the
   `summary`. (If there were no rows: `noData` only — no group bands — exactly as 007b.)
5. **No groups declared:** identical to 007b (no group bands ever emitted).

### Ordering is derived from `template.groups`, never from the `Set`

`brokenGroups` is a `Set<String>` (unordered). The emission order is derived from
**`template.groups`** (the authored, outermost-first list), filtered to the names present in
`brokenGroups`:
- **Headers** iterate that filtered list **forward** (outermost→innermost).
- **Footers** iterate it **reversed** (innermost→outermost).

An implementation must **not** iterate `brokenGroups` directly for ordering. When a group has
multiple header (or footer) bands, they emit in **authored `template.bands` order** — `GroupBandIndex`
(§6) preserves that encounter order.

### Row context & variable snapshot per band

| Band | `row` passed to the resolver | `variables` snapshot |
|---|---|---|
| `groupHeader` | the **first** row of the new group (the current `row` at the break / first data row) | `calc.values` **after** advance (post-reset, current row folded) |
| `groupFooter` | the **last** row of the ended group (`prevRow`) | `prevValues` (the pre-reset subtotal) |
| `detail` | the current `row` | `calc.values` |
| `title`/`summary`/`noData` | `null` | `calc.values` |

So a `groupHeader` resolves `$F{region}` to the new group's key (first row), and a `groupFooter`
resolves `$V{regionTotal}` to the group's complete subtotal (last row, pre-reset) and `$F{}` to the
last row's fields.

### Why this needs no calculator change (subtotal correctness)

The footer's subtotal must be the value as of the group's last row, **before** the breaking row's
reset. The calculator's `advance(breakingRow)` does break-detection, reset, and fold in one call —
so `calc.values` *after* that call already shows the reset (new group's) subtotal. The driver
therefore reads the footer subtotal from `prevValues`, captured after the *previous* row. Traced:

```
groups: [region, city]   vars: citySub (reset:city), regionSub (reset:region)

first row r1:  all headers outer→inner  (header region, header city), row=r1, vars=calc.values
  detail r1, r2, ...
  detail rN              (city A's last row; prevValues = {citySub: S_cityA, regionSub: ...}, prevRow=rN)
city breaks at rN+1:
  groupFooter city(A)    row=rN (prevRow), vars=prevValues  -> citySub = S_cityA   ✔ pre-reset
  groupHeader city(B)    row=rN+1,         vars=calc.values  -> citySub = (just rN+1)
  detail rN+1, ...
region breaks at rM+1 (cascade -> {region, city}):
  groupFooter city(B)    \  footers inner->outer, both from the SAME prevValues snapshot
  groupFooter region(W)  /  citySub = S_cityB, regionSub = S_regionW   ✔
  groupHeader region(E)  \  headers outer->inner, vars=calc.values
  groupHeader city(E/C)  /
  ...
end of data:
  groupFooter city(...)  \  all footers inner->outer, from final prevValues
  groupFooter region(...)/
  summary
```

This reuses the calculator's existing `brokenGroups` + reset machinery untouched.

## §6 — Components & files

**Modify (domain + serialization):**
- `lib/src/domain/report_band.dart` — add the optional `final String? group;` (constructor, field).
- `lib/src/domain/serialization/report_codec.dart` — round-trip `group` (encode when non-null;
  decode as `String?`).

**Create (`rendering/fill/`):**
- `lib/src/rendering/fill/group_band_index.dart` — `GroupBandIndex`, a small **pure** unit built
  from a `ReportTemplate` + a `ReportDiagnostics`. Responsibilities:
  - Validate duplicate group names → error diagnostic (§4).
  - Validate each `groupHeader`/`groupFooter` band's `group`: **null** → error
    (`groupHeader band must declare a group`); **unknown** (not in `template.groups`) → error
    (`band references unknown group "<name>"`). Malformed bands are **excluded** from the index
    (render-don't-crash; the rest of the report still renders).
  - Index the valid group bands by `(group name)`, **preserving authored `template.bands` order**.
  - Expose `headersFor(String groupName) → List<ReportBand>` and
    `footersFor(String groupName) → List<ReportBand>`.
  - Independently testable (pure: template + diagnostics in, lookups out).

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/report_filler.dart` — the sequencing (§5), factored into focused private
  methods (e.g. `_emitGroupHeaders(names, row)`, `_emitGroupFooters(names, prevRow, prevValues)`)
  driven by `calc.brokenGroups`, `template.groups` ordering, the `GroupBandIndex`, and the
  `prevValues`/`prevRow` state. The existing `emit(...)` helper for flat bands is reused for the
  detail/title/summary/noData path.

**No change:** `filled_report.dart` (IR unchanged, §1), `fill_eval_context.dart`,
`element_resolver.dart` (group-band elements resolve through the **same** resolver — page-scoped
rejection, `!ERR`, missing-field warnings all apply unchanged), `variable_calculator.dart` (005b).

## §7 — Diagnostics & error policy

007c adds almost no new diagnostic surface — group-band **elements** resolve through the existing
`ElementResolver`, so a `$V{PAGE_NUMBER}` in a group header is rejected (error + authored text
preserved), a bad expression yields `!ERR`, and a missing `$F{}` warns (deduped) — all exactly as in
007b. The genuinely new diagnostics are **structural template validation** (render-don't-crash,
never thrown):

| Condition | Severity | Behavior |
|---|---|---|
| Duplicate `ReportGroup.name` | **error** | continue; calculator behavior is ambiguous — the diagnostic flags it (§4) |
| `groupHeader`/`groupFooter` band with `group == null` | **error** | exclude the band from the index; continue |
| `groupHeader`/`groupFooter` band with `group` naming an undeclared group | **error** | exclude the band; continue |
| `group` set on a non-group band type | (none) | ignored silently |

Fill still fail-fasts (throws) only on a variable/group **expression parse** failure (005b/007b
behavior, unchanged).

## §8 — Testing

**`GroupBandIndex` (unit):**
- Valid index: `headersFor`/`footersFor` return the right bands.
- Multiple header (and footer) bands for one group are returned in **authored order** (pins §5
  ordering).
- `group == null` on a group band → error diagnostic + excluded.
- Unknown group name on a group band → error diagnostic + excluded.
- Duplicate group names → error diagnostic.

**`ReportFiller` (grouping):**
- **Single group:** stream is `groupHeader, detail…, groupFooter` per group, in order.
- **Footer subtotal uses the pre-reset snapshot** (the crux): assert the footer shows the group's
  full subtotal (e.g. `15`), not the post-reset value (e.g. `7`).
- **Header shows the group key** via `$F{}` (resolved against the first row of the group).
- **Footer shows last-row `$F{}` + `$V{}` subtotal** (resolved against the last row + `prevValues`).
- **Nested groups:** header order outer→inner; footer order inner→outer; an outer break cascades
  (emits inner+outer footers then inner+outer headers); subtotals correct at each level.
- **Multiple headers/footers for one group** emit in authored order (end-to-end, complements the
  index unit test).
- **End-of-data footers** for all groups (inner→outer) emit **before** `summary`.
- **Page-scoped reference in a group-band element** → error diagnostic + authored text preserved
  (reuses the resolver).
- **Determinism:** re-filling identical inputs yields an equal `FilledReport`.

**Regression (must stay green, unchanged):**
- All existing 007b `report_filler` tests (no-groups path is byte-for-byte identical).
- Groups declared but **no** group bands present → variable resets happen (005b), but **no** group
  bands emit (007b behavior preserved).
- All existing 005b `variable_calculator` tests (the calculator is untouched).

**Codec:** `ReportBand.group` round-trips; omitted from JSON when null; a band without `group`
decodes to `group == null`.

**Layer boundary:** unchanged — `group_band_index.dart` and the filler changes stay within the
`rendering/fill/` headless seam (the existing boundary test already covers the directory).

## §9 — The IR is unchanged

`FilledReport`/`FilledBand` are **not** modified. A grouped fill simply produces more `FilledBand`
instances (of type `groupHeader`/`groupFooter`) in the existing ordered `bands` list, each with its
resolved elements and frozen variable snapshot. This is the reason the 007b spec left the IR
intentionally "incomplete/unfrozen" — 007c populates the group-band instances without changing the
shape.

## §10 — Design decisions

1. **Driver-only feature.** All grouping *computation* (key evaluation, break detection with
   cascade, group-scoped resets) already exists in the 005b `VariableCalculator`. 007c only
   *sequences band instances* around that computation; the calculator is reused unchanged.
2. **Name-based `ReportBand.group` link in the flat band list** (vs. moving bands into
   `ReportGroup`). Keeps all bands in one ordered `template.bands` list (consistent with how
   title/detail/summary live there) and mirrors the existing `ReportVariable.resetGroup` name link.
   Minimal additive domain change.
3. **Header = first row, footer = last row** (JasperReports-style). Lets a header show the group key
   via `$F{}` and a footer show last-row fields plus `$V{}` subtotals. The alternative (both no-row)
   was rejected as less capable.
4. **Subtotal correctness via a driver-held `prevValues`/`prevRow` snapshot** — no calculator
   change. The footer reads the pre-reset subtotal the driver already captured after the previous
   row; `brokenGroups` tells the driver which groups ended (§5).
5. **Ordering derived from `template.groups`, not the `brokenGroups` `Set`** — the authored
   outer-first order is the single source of nesting truth; the `Set` is membership-only. Multiple
   bands per `(type, group)` preserve authored `template.bands` order via `GroupBandIndex`.
6. **Unique `ReportGroup.name` is an explicit invariant**, validated with an error diagnostic — the
   005b calculator already assumes it (Set-keyed `brokenGroups`, name-keyed `resetGroup`).
7. **Structural validation is render-don't-crash** (error diagnostics + exclude the offending band),
   not fail-fast — consistent with 007b, which fail-fasts only on expression *parse* failures. The
   report still renders without the malformed band.
8. **Schema version is not bumped** (stays at 1). The library is **pre-1.0 and unreleased**, so
   there are no in-the-wild builds to protect with a forward-compat rejection, and `ReportBand.group`
   is an optional additive field — the same shape and treatment as 007b's `TextElement.expression`
   (also added at schema 1). The forward-compat tradeoff (a hypothetical older build silently
   dropping group bands) is **consciously accepted** for now; a dedicated schema-versioning pass
   before 1.0 will settle the bump policy across all additive fields. (Note: `groupHeader`/
   `groupFooter` are already legal `BandType` values today, so a stale build already ignores group
   bands regardless of this field.)
9. **`FilledBand` IR unchanged** — no `group` field; Layout (008) consumes the template + the stream
   and lays bands out in order (§1, §9).

## §11 — File plan

| File | Change |
|---|---|
| `lib/src/domain/report_band.dart` | + optional `group` field |
| `lib/src/domain/serialization/report_codec.dart` | round-trip `group` (encode-if-non-null / decode `String?`) |
| `lib/src/rendering/fill/group_band_index.dart` | **new** — validate + index group bands; lookups |
| `lib/src/rendering/fill/report_filler.dart` | group-band sequencing (private emit helpers + state) |
| `test/domain/serialization/report_codec_*` | `ReportBand.group` round-trip (+ omitted-when-null) |
| `test/rendering/fill/group_band_index_test.dart` | **new** — index validation + ordering |
| `test/rendering/fill/report_filler_test.dart` | grouping sequence, subtotals, nesting, determinism |
| `CHANGELOG.md` | 007c entry |

## §12 — Review history

**Pre-write review (R1), folded in:**
1. *Schema bump.* Reviewer: adding `ReportBand.group` at schema 1 lets a stale build silently
   mis-render group documents; the codec contract says bump on every schema change. **Resolution:**
   the library is unreleased / pre-1.0 and everything is subject to change, and the field is an
   optional additive field matching 007b's `expression` (also schema 1). Decision: **no bump** now;
   the conscious tradeoff is documented (§10 #8) and a pre-1.0 versioning pass will settle the
   policy. (Verified: `kReportSchemaVersion == 1`; `TextElement.expression` did not bump; there is
   no default-migrations registry yet and no production decode call site — the 011 facade does not
   exist.)
2. *Group-name uniqueness.* Reviewer: 007c adds a second name-keyed link (`ReportBand.group`) while
   the calculator collapses breaks into a `Set<String>`; duplicate names make break detection,
   resets, and routing ambiguous. **Folded in:** uniqueness is now a stated invariant **and**
   validated (error diagnostic, §4/§7), with a test (§8).
3. *Ordering too implicit.* Reviewer: order is semantic in `template.groups` and `template.bands`,
   but `brokenGroups` is a `Set`; the spec should state ordering is derived from `template.groups`
   (not `Set` iteration) and that the index preserves authored band order. **Folded in:** §5
   ("Ordering is derived from `template.groups`…") + §8 authored-order tests.
4. *Non-finding — no `FilledBand.group`.* Reviewer confirmed leaving the filled IR unchanged is
   consistent with Layout consuming the template + the stream. **No change** (§1, §9).
