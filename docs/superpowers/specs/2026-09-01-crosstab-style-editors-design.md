# Crosstab Style Editors (Spec C)

**Date:** 2026-09-01
**Status:** Implemented.
**Depends on:** `2026-08-30-crosstab-engine-design.md` (Spec A, shipped `63a46ee`) and
`2026-09-01-crosstab-designer-authoring-design.md` (Spec B, shipped `06c4125`).
**Layer:** designer view layer only. No domain field, no codec change, no controller method, no
engine change, no schema bump, no public API change.

## Goal

Make the eight crosstab appearance slots **authorable**. Every one of them already renders; none of
them can be edited. This spec adds the editors and nothing else.

## Why this, and why not the rest of Spec B's deferral list

Spec B deferred nine items and Spec A labelled the whole group *"C — Polish … Optional,
evidence-driven."* Those nine are three unrelated projects, and only one of them has its evidence
already in the repository:

| Group | Items | Model state | Verdict |
|---|---|---|---|
| **C1 (this spec)** | 6 `CrosstabStyle` slots + 2 `CrosstabMeasure` overrides | shipped and rendering | **build** |
| C2 | across-first slice order, fit/scale columns, derived measures, cell templates | nothing exists | parked — no report needs them |
| C3 | crosstab in `NestedScope`, WYSIWYG canvas, drag-resize columns, crosstab clipboard | mixed | parked |

C1 is not a feature request. The capability ships today and is simply unreachable from the UI, which
makes it a defect. C2 would mean inventing the demand that Spec A said to wait for: four new domain
fields, four codec changes, new `validate()` rules, planner work and a schema version bump. C3's
WYSIWYG item is architecturally blocked — the designer holds a `JetDataSchema`, not rows, so it
cannot fold the data that determines a crosstab's real row and column counts.

## What already exists

The engine side is finished. `crosstab_planner.dart` resolves cell appearance through a documented
three-layer cascade:

```dart
JetTextStyle _cellTextStyle(CrosstabMeasure measure) =>
    measure.cellTextStyle ?? style.cellText ?? _cellDefaultText;

JetBoxStyle? _cellBoxStyle(CrosstabMeasure measure) =>
    measure.cellBoxStyle ?? style.cellBox;
```

| Seam | State |
|---|---|
| `CrosstabStyle.headerText/headerBox/cellText/cellBox/totalText/totalBox` | Declared, thunk-`copyWith`, codec round-trips, **honoured by the planner** |
| `CrosstabMeasure.cellTextStyle/cellBoxStyle` | Same — and **not listed in Spec B's deferral**, which named six slots where there are eight |
| `setCrosstabStyle(String, CrosstabStyle)` | Exists; takes a whole style, exactly what an editor produces |
| `updateCrosstabMeasure(String, String, CrosstabMeasure Function(CrosstabMeasure))` | Exists; thunk-based |
| `_ColorField`, `_FontFamilyRow`, `_StyleToggleGroup`, `_AlignSegments` | Exist in `style_editors.dart` |

**There is no visibility barrier.** `style_editors.dart`, `element_inspector.dart` and
`crosstab_inspector.dart` are all `part of properties_panel.dart` — one library. The four low-level
editors are already callable from the crosstab inspector today.

Spec B's stated blocker was therefore about **duplication volume**, not access: composing eight
slots the way the element inspector composes one would mean repeating ~75 lines eight times, in a
file the god-file split program had just brought under control. That is the problem this spec
solves, and it is why the extraction — not the crosstab UI — is the architectural core.

## Locked decisions

### 1. Null means "inherit"; the first edit materializes; a reset clears

Every slot is nullable, and null falls through the planner's cascade. The editor shows the
**effective** value it would inherit, so the controls are never blank or misleading. Any edit
commits a concrete style. Each role section carries a reset action that writes `null` back.

This matches the thunk-`copyWith` idiom the DRY refactor standardized (`headerText: () => null`
clears) and preserves the codec's omit-when-null behaviour: a crosstab whose appearance is never
touched serializes byte-identically to one authored before this spec.

The alternative — materializing all eight slots at creation — was rejected: it would write eight
style objects into every `.jetreport` file that has a crosstab, changing existing documents on
resave for no user-visible gain.

### 2. Three flat sections, matching every other panel

Header / Cells / Totals each get their own `SectionLabel`. The designer has **no accordion or
disclosure primitive anywhere** — every panel is a flat scroll of `SectionLabel` + content. Adding
one would be new shared UI vocabulary with its own tests, for a panel-height problem the existing
panels already tolerate. A role selector was rejected for a different reason: it hides two of three
roles behind a control, so a report author cannot see at a glance that Totals was never styled.

The three roles are structurally identical — each is exactly `{JetTextStyle?, JetBoxStyle?}` — so
they are one parameterized function invoked three times, not three hand-written sections.

### 3. Per-measure overrides live in the measure card

`measure.cellTextStyle` only has meaning beside that measure's expression and aggregate, so it is
edited there rather than in a fourth appearance section. The measure card already exists
(`_crosstabMeasureCard`) and already holds name / expression / aggregate / format.

### 4. The extraction is validated by the existing suites, not by new tests

`_TextStyleEditor` and `_BoxStyleEditor` each have an **existing consumer** that is refactored onto
them first:

| New widget | Existing consumer | Existing behaviour it must preserve |
|---|---|---|
| `_TextStyleEditor` | text-element Font section, `element_inspector.dart` ~128-200 | family / size / colour / B-I-U / align, all committing through `setTextStyle` |
| `_BoxStyleEditor` | shape-element Appearance section, `element_inspector.dart` ~515-570 | fill / outline / width; **a line shape drops the fill box** ("a line has no interior") |

Refactoring those two call sites first means the whole element-inspector test suite exercises the
new widgets before any crosstab test is written. If the extraction changes behaviour, those tests
fail. That is the safety net; new tests cover only what is genuinely new.

`_BoxStyleEditor` therefore needs a `showFill` flag to preserve the line-shape case. Missing it
would silently regress a shipped behaviour that no crosstab slot would ever exercise.

## 1. New part file

`layout/panels/properties/fields/style_section.dart`, `part of '../../properties_panel.dart'`.

```dart
/// A composed JetTextStyle editor: family + size + colour on one row,
/// B/I/U + alignment on the next. Commits one whole style per change.
class _TextStyleEditor extends StatelessWidget {
  const _TextStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
  });
  final String keyBase;
  final JetTextStyle style;
  final ValueChanged<JetTextStyle> onCommit;
}

/// A composed JetBoxStyle editor: fill + outline swatches and a width preset.
/// [showFill] is false for shapes with no interior (the line shape).
class _BoxStyleEditor extends StatelessWidget {
  const _BoxStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
    this.showFill = true,
  });
  final String keyBase;
  final JetBoxStyle style;
  final ValueChanged<JetBoxStyle> onCommit;
  final bool showFill;
}
```

Both are pure composition over the four editors already in `style_editors.dart`. Neither holds
state; both keep the panel's `_p` key-prefix convention so existing widget-test finders keep
working.

## 2. The role section

One function, three calls. It owns decision 1 in a single place:

```dart
/// One appearance role — the label, its text and box editors, and the reset
/// that clears both slots back to inherited.
///
/// [text] / [box] are the authored slots (null = inherited); [effectiveText] /
/// [effectiveBox] are what the planner's cascade would resolve, and are what
/// the editors display while the slots are null.
List<Widget> _crosstabRoleSection({
  required String label,
  required String keyBase,
  required JetTextStyle? text,
  required JetBoxStyle? box,
  required JetTextStyle effectiveText,
  required JetBoxStyle effectiveBox,
  required ValueChanged<JetTextStyle> onText,
  required ValueChanged<JetBoxStyle> onBox,
  required VoidCallback onReset,
});
```

The reset action is shown only when at least one of the two slots is non-null — an always-visible
reset on an untouched role would suggest state that is not there.

The three call sites in `_crosstabInspector` commit through the existing controller method:

```dart
controller.setCrosstabStyle(id, crosstab.style.copyWith(headerText: () => next));
```

The effective values mirror the planner's own defaults. They are re-derived in the panel rather than
imported from the planner, exactly as the width warning re-derives its geometry (spec 035 / Spec B
§4): the render layer is not a designer dependency, and the panel must work with no data source
attached.

**Three slots have a dual fallback, and the section displays the dominant one.** `headerText`,
`totalText` and `totalBox` are each read at two sites with different defaults while unset:

| Slot | Site | Default while null |
|---|---|---|
| `headerText` | column headers (`_columnHeaderText`) | `JetTextStyle(align: center)` — **displayed** |
| `headerText` | the row-label stub column (`_rowLabelText`) | `JetTextStyle.fallback` (left) |
| `totalText` | total *values* (`_totalCellText`) | `cellText` if set, else `JetTextStyle(align: right)` — **displayed** |
| `totalText` | total *labels* (`_totalLabelText`) | cascades to `_rowLabelText` (left) |
| `totalBox` | total *values* (`_cellBoxStyle`'s caller, :653) | `cellBox` if set, else `JetBoxStyle.none` — **displayed** |
| `totalBox` | total *labels* (:629) | `style.headerBox` — the HEADER box, not `cellBox` |

**Totals inherits from Cells, not from the bare default.** `_totalCellText` is
`style.totalText ?? _cellTextStyle(measure)`, and `_cellBoxStyle`'s caller is
`style.totalBox ?? _cellBoxStyle(measure)` — so an unset Totals slot reaches the renderer default
only when Cells is *also* unset. The Totals section therefore displays
`ct.style.cellText ?? _kCrosstabCellDefault`, not the constant alone. An earlier draft of this spec
listed only the terminal default in the table above, and the implementation plan copied the table
rather than the planner; the result was a panel that showed a bare default while the report rendered
the authored Cells style. The two-hop case now has its own test.

**Cells and Totals both skip the measure layer, and this is an accepted approximation, not a bug.**
The planner's real cascade for a value cell starts one layer *lower* than either section shows:
`measure.cellTextStyle`/`cellBoxStyle` first, then the crosstab style, then the bare default. Both
the Cells and Totals sections display only the crosstab-level cascade — `ct.style.cellText ??
_kCrosstabCellDefault` and its box equivalent — because with N measures on one crosstab there is no
single per-measure value that could be shown in a section that isn't scoped to one measure. This
means a measure with its own `cellTextStyle`/`cellBoxStyle` override (authored in its own card, see
§3) makes the Cells/Totals sections' displayed value diverge from what the renderer actually prints
for that measure. Showing the crosstab-level value regardless is still the right choice — the
alternative is no display, or an arbitrary pick among measures — but the code comments must say so
rather than implying (as an earlier version did) that the displayed value is unconditionally what
the planner will resolve.

The section shows the first of each pair: column headers outnumber the single row-label column, and
total values outnumber their labels. The approximation is confined to alignment, and it is
self-correcting — the planner's own comment records that "an authored `headerText` is honoured as
written, alignment included", so **both sites collapse to the authored value the moment the slot
stops being null**. The preview is therefore inexact only while it is a preview; it becomes exact
at the first edit.

This is documented in the code, not merely here: the alternative (showing two alignments per role,
or splitting Header into two sections) would expose a renderer-internal distinction that disappears
as soon as the author touches it.

**This mirroring is the one real risk in this spec** — the defaults are stated in two places and can
drift. The mitigation is a **pair of literals, one pinned on each side**: no single test can compare
them directly, because the planner's defaults are private to the render library and the panel's to
the designer library. So the designer suite pins the panel's value and the render suite pins the
planner's, and a change to either side fails loudly. (An earlier draft claimed one test could assert
the two are equal. That test cannot be written in Dart, and a mitigation that cannot compile is worse
than none, because it stops anyone looking. The render-side pin for the centred column-header default
was in fact missing until this was checked; the right-aligned cell default was already covered by
`crosstab_planner_test.dart`.) The alternative (exporting the planner's defaults into the domain layer) is a larger change
than this spec's scope and would move render-layer policy into the model.

## 3. Measure card additions

`_crosstabMeasureCard` gains the same two editors for `cellTextStyle` / `cellBoxStyle`, under their
own sub-label, committing through the existing thunk:

```dart
controller.updateCrosstabMeasure(crosstabId, measure.id,
    (CrosstabMeasure m) => m.copyWith(cellTextStyle: () => next));
```

Their inherited values come from the crosstab's own `cellText` / `cellBox` — one cascade layer up,
not from the renderer default — so the displayed inheritance is truthful at each level.

## 4. Localization

Reused as-is: `propertiesFont`, `fontSizeLabel`, `fontFamilyDefault`, `propertiesAppearance`,
`propertiesFill`, `propertiesOutline`, `propertiesOutlineWidth`.

New keys (English, Turkish, German — ARBs are the source of truth, generated Dart is never
hand-edited):

| Key | English |
|---|---|
| `crosstabStyleHeader` | Header cells |
| `crosstabStyleCells` | Data cells |
| `crosstabStyleTotals` | Total cells |
| `crosstabStyleReset` | Reset to default |
| `crosstabStyleInherited` | Inherited |
| `crosstabMeasureStyle` | Cell override |

## 5. Testing

| Behaviour | Assertion |
|---|---|
| Extraction is behaviour-preserving | The existing element-inspector suites pass unchanged against the refactored call sites — no new tests, no edited expectations |
| Line shape keeps its missing fill box | The existing shape test still finds no fill swatch for a line; `showFill: false` is what preserves it |
| Inherit is displayed, not blank | With all slots null, each role's editors show the planner's cascade values |
| First edit materializes | Editing header text on an untouched crosstab writes a concrete `headerText` and leaves the other five slots null |
| Reset clears | Reset writes `null` back, and the section returns to showing inherited values |
| Reset is conditional | The reset action is absent on an untouched role and present once either slot is set |
| Panel/planner defaults agree | The panel's fallback for each of the three roles equals the planner's dominant default: `align: center` for Header, `align: right` for Cells and Totals |
| Dual fallback collapses on edit | Authoring `headerText` makes `_columnHeaderText` and `_rowLabelText` resolve to the same style — the preview's approximation ends at the first edit |
| Measure override cascades | A measure's inherited value is the crosstab's `cellText`, not the renderer default |
| One undo step per change | Each committed edit is a single undoable step, as bands and elements already are |
| Codec is untouched | A crosstab with no authored appearance round-trips byte-identically |

**Goldens: none move.** No designer golden contains a crosstab (verified during Spec B), and this
spec changes no default, so an unstyled crosstab renders exactly as it does today. The element
inspector's own goldens are the check on the extraction: if the refactor shifts a single pixel in
the Font or Appearance section, they fail — which is the intended alarm, not an expected diff to
regenerate.

## Out of scope

Everything in C2 and C3 above. In particular this spec adds **no** new appearance capability: it
exposes exactly the slots the planner already reads, and adds no slot the engine would ignore.

## Risks

- **Two-place defaults.** Covered above with a cross-checking test; accepted deliberately rather
  than moving render policy into the domain layer.
- **Panel height.** The crosstab inspector becomes the tallest in the app. Accepted under decision
  2; if it proves unusable in the GUI walk, a disclosure primitive is a separate change that would
  benefit every panel, not a crosstab-specific patch.
- **Refactor blast radius.** `element_inspector.dart` is a shipped, well-tested file and the
  extraction touches its two most-tested sections. Mitigated by refactoring it *first*, as its own
  reviewable step, before any crosstab code exists — so a failure there is unambiguous.
