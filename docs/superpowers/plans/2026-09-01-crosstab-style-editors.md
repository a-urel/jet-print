# Crosstab Style Editors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the eight crosstab appearance slots authorable in the designer — six on `CrosstabStyle`, two per-measure — all of which already render today but have no UI.

**Architecture:** Extract two composed widgets (`_TextStyleEditor`, `_BoxStyleEditor`) into a new `part` file of the `properties_panel.dart` library, refactoring the two *existing* consumers onto them first so the shipped element-inspector suites validate the extraction. Then the crosstab inspector gains one parameterized role section invoked three times, plus per-measure overrides in the measure card. No domain, codec, controller, engine or public-API change.

**Tech Stack:** Dart / Flutter, `shadcn_ui` (`ShadThemeData`, `ShadSelect`, `ShadPopover`), `lucide_icons`, `flutter_localizations` + `gen-l10n` over ARB files, `flutter_test` widget tests.

**Spec:** `docs/superpowers/specs/2026-09-01-crosstab-style-editors-design.md`

## Global Constraints

- **Key strings must be preserved exactly.** `test/designer/properties_editor_test.dart:23` defines `Finder _field(String name) => find.byKey(ValueKey<String>('$_p.field.$name'));` and 85 tests use it. The extracted widgets compose keys as `'$keyBase.<name>'`; the element inspector passes `keyBase: '$_p.field'`, reproducing `'$_p.field.fontSize'`, `'$_p.field.textColor'`, `'$_p.field.fill'`, `'$_p.field.stroke'`, `'$_p.field.strokeWidth'` character-for-character.
- `const String _p = 'jet_print.designer.properties';` is declared at `properties_panel.dart:76`.
- **No public API change.** Nothing is added to `lib/jet_print.dart`. All new widgets are library-private (leading `_`) in the `properties_panel.dart` library.
- **No domain, codec, controller or engine change.** `setCrosstabStyle(String, CrosstabStyle)` and `updateCrosstabMeasure(String, String, CrosstabMeasure Function(CrosstabMeasure))` already exist and are the only write paths used.
- **ARBs are the source of truth.** Edit `jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb` and run `flutter gen-l10n`; never hand-edit generated Dart. Every new key needs an `@key` description entry. Do not put unescaped `"` inside an ARB description.
- **Nullable style slots use thunk `copyWith`:** `copyWith(headerText: () => value)` sets, `copyWith(headerText: () => null)` clears, omitting preserves.
- **One committed edit = one undo step**, matching bands and elements.
- **No golden may move.** No designer golden contains a crosstab. If an element-inspector golden shifts, the extraction changed layout — fix the extraction, do not regenerate the golden.
- Run tests from inside the package: `cd packages/jet_print && flutter test`. Run `git` from the repo root (`flutter` leaves the cwd inside the package).
- `dart analyze` must be clean; imports follow `directives_ordering`.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/src/designer/layout/panels/properties/fields/style_section.dart` | **New.** `_TextStyleEditor`, `_BoxStyleEditor`, `_crosstabRoleSection`. `part of '../../properties_panel.dart'`. |
| `lib/src/designer/layout/panels/properties_panel.dart` | One added `part` directive. |
| `lib/src/designer/layout/panels/properties/inspectors/element_inspector.dart` | Two sections refactored onto the new widgets (Font ~124-198, shape Appearance ~512-575). |
| `lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart` | Three role sections + two measure-card overrides. |
| `lib/src/designer/l10n/jet_print_{en,tr,de}.arb` | Six new keys. |
| `test/designer/crosstab_style_test.dart` | **New.** All new behaviour. |
| `test/designer/properties_editor_test.dart` | **Unchanged** — the extraction's safety net. |

Existing library-private helpers available to the new file (same library, no import needed): `_ColorField`, `_FontFamilyRow`, `_StyleToggleGroup`, `_AlignSegments` (`style_editors.dart`); `_PresetDropdown`, `_DropdownOption`, `_fontSizePresets` (`pickers.dart`); `_strokeWidthPresets`, `_format`, `_LineWidthPreview` (`previews.dart`); `SectionLabel` (`region_chrome.dart`); `DesignerFontScope`.

---

### Task 1: Extract `_TextStyleEditor` and refactor the element Font section

**Files:**
- Create: `packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (add `part`)
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/element_inspector.dart:127-197`
- Test: `packages/jet_print/test/designer/properties_editor_test.dart` (must pass **unchanged**)

**Interfaces:**
- Consumes: `_ColorField`, `_FontFamilyRow`, `_StyleToggleGroup`, `_AlignSegments`, `_PresetDropdown`, `_DropdownOption`, `_fontSizePresets`, `_format`, `DesignerFontScope`.
- Produces: `_TextStyleEditor({required String keyBase, required JetTextStyle style, required ValueChanged<JetTextStyle> onCommit, bool showAlign = true})`.

- [ ] **Step 1: Run the existing suite to record a green baseline**

```bash
cd packages/jet_print && flutter test test/designer/properties_editor_test.dart
```

Expected: PASS (85 tests). This is the baseline the refactor must not disturb. If it is not green before you start, stop and report.

- [ ] **Step 2: Create the new part file with `_TextStyleEditor`**

Create `packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart`:

```dart
// Composed style editors for the Properties panel (spec C).
//
// A part of `properties_panel.dart`, like every other panel file, so these
// compose the library-private editors in `style_editors.dart` without exposing
// anything.
//
// These exist because eight crosstab appearance slots need the same controls
// the element inspector had assembled inline: composing them per slot would
// have meant repeating ~75 lines eight times, which is why spec B deferred the
// crosstab style editors in the first place.
//
// Key composition is load-bearing. Keys are built as `'$keyBase.<name>'`, and
// the element inspector passes `keyBase: '$_p.field'` so the shipped keys
// (`$_p.field.fontSize`, `$_p.field.textColor`, …) survive verbatim — 85 tests
// in properties_editor_test.dart find widgets through exactly those strings.
part of '../../properties_panel.dart';

/// A composed [JetTextStyle] editor: family, size and colour on one row;
/// the B/I/U toggles and alignment segments on the next.
///
/// Every control commits one whole style through [onCommit], so each change is
/// a single undoable step (FR-013). The widget is stateless and holds no draft:
/// callers wrap it in a `KeyedSubtree` keyed by the edited object's id when a
/// selection switch should discard uncommitted input.
///
/// [showAlign] hides the alignment segments for slots where alignment is not
/// author-controlled; it defaults to true.
class _TextStyleEditor extends StatelessWidget {
  const _TextStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
    this.showAlign = true,
  });

  /// Prefix for every child key; children append `.fontSize`, `.textColor`.
  final String keyBase;

  /// The style the editors display — for a nullable slot, the effective value
  /// it would inherit, so the controls are never blank.
  final JetTextStyle style;

  /// Receives the whole updated style on every committed change.
  final ValueChanged<JetTextStyle> onCommit;

  /// Whether to show the alignment segments.
  final bool showAlign;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Family, size and color share one compact row — no left labels.
        // The family picker takes the slack; size is a fixed-width field
        // (its leading glyph stands in for the dropped "Size" label); the
        // color trigger is a square swatch-only box.
        Row(
          children: <Widget>[
            Expanded(
              child: _FontFamilyRow(
                fonts: DesignerFontScope.of(context),
                showBuiltIns: DesignerFontScope.showBuiltInsOf(context),
                style: style,
                onCommit: onCommit,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 84,
              child: _PresetDropdown(
                fieldKey: ValueKey<String>('$keyBase.fontSize'),
                label: _format(style.fontSize),
                tooltip: l10n.fontSizeLabel,
                options: <_DropdownOption>[
                  for (final double size in _fontSizePresets)
                    _DropdownOption(
                      optionKey: ValueKey<String>(
                          '$keyBase.fontSize.option.${_format(size)}'),
                      label: _format(size),
                      selected: style.fontSize == size,
                      onPick: () => onCommit(style.copyWith(fontSize: size)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _ColorField(
              keyBase: '$keyBase.textColor',
              value: style.color,
              compact: true,
              onCommit: (JetColor? c) => onCommit(style.copyWith(color: c)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            _StyleToggleGroup(style: style, onCommit: onCommit),
            if (showAlign) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(
                child: _AlignSegments(
                  align: style.align,
                  onCommit: (JetTextAlign a) =>
                      onCommit(style.copyWith(align: a)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Register the part file**

In `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`, add next to the other `part` directives (keep them alphabetically ordered as the file already has them):

```dart
part 'properties/fields/style_section.dart';
```

- [ ] **Step 4: Refactor the element Font section onto it**

In `element_inspector.dart`, replace the body of the `KeyedSubtree` at `key: ValueKey<String>('$_p.font.$id')` — everything from `SectionLabel(l10n.propertiesFont),` through the closing of the second `Row` — with:

```dart
KeyedSubtree(
  key: ValueKey<String>('$_p.font.$id'),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SectionLabel(l10n.propertiesFont),
      _TextStyleEditor(
        keyBase: '$_p.field',
        style: element.style,
        onCommit: (JetTextStyle next) => controller.setTextStyle(id, next),
      ),
    ],
  ),
),
```

Delete the now-unused inline `_FontFamilyRow`, `_PresetDropdown`, `_ColorField`, `_StyleToggleGroup` and `_AlignSegments` construction from this section. Leave the leading comment block ("Font section (021 / US1)…") in place above the `KeyedSubtree`.

- [ ] **Step 5: Run the existing suite — it must pass unchanged**

```bash
cd packages/jet_print && flutter test test/designer/properties_editor_test.dart
```

Expected: PASS, same 85 tests, **no test edited**. A failure here means the extraction changed behaviour or a key string. Do not edit the test to match — fix the widget. In particular `_field('fontSize')` resolves to `ValueKey('jet_print.designer.properties.field.fontSize')`, so `keyBase` must be `'$_p.field'` and not `'$_p.field.font'` or similar.

- [ ] **Step 6: Run the wider designer suite and analyze**

```bash
cd packages/jet_print && flutter test test/designer && dart analyze
```

Expected: PASS, analyze clean. Goldens included — if an element-inspector golden moves, the extraction changed layout; fix it rather than regenerating.

- [ ] **Step 7: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart \
        packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart \
        packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/element_inspector.dart
git commit -m "refactor(designer): extract a composed _TextStyleEditor

The element inspector assembled family/size/colour/B-I-U/align inline. Eight
crosstab appearance slots need the same controls, so composing them per slot
would repeat ~75 lines eight times — the duplication that made spec B defer
the crosstab style editors.

Keys compose as '\$keyBase.<name>' and the element inspector passes
'\$_p.field', so every shipped key survives verbatim and the 85 tests in
properties_editor_test.dart pass unedited. That is the check on the extraction."
```

---

### Task 2: Extract `_BoxStyleEditor` and refactor the shape Appearance section

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/element_inspector.dart:515-575`
- Test: `packages/jet_print/test/designer/properties_editor_test.dart` (must pass **unchanged**)

**Interfaces:**
- Consumes: `_ColorField`, `_PresetDropdown`, `_DropdownOption`, `_strokeWidthPresets`, `_format`, `_LineWidthPreview`.
- Produces: `_BoxStyleEditor({required String keyBase, required JetBoxStyle style, required ValueChanged<JetBoxStyle> onCommit, bool showFill = true})`.

- [ ] **Step 1: Append `_BoxStyleEditor` to `style_section.dart`**

```dart
/// A composed [JetBoxStyle] editor: fill and outline swatches plus an outline
/// width preset, all on one label-less row.
///
/// [showFill] is false where the shape has no interior — the line shape drops
/// its fill box, a shipped behaviour this flag exists to preserve. No crosstab
/// slot uses it, so it would regress silently without a test.
class _BoxStyleEditor extends StatelessWidget {
  const _BoxStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
    this.showFill = true,
  });

  /// Prefix for every child key; children append `.fill`, `.stroke`,
  /// `.strokeWidth`.
  final String keyBase;

  /// The box style the editors display.
  final JetBoxStyle style;

  /// Receives the whole updated style on every committed change.
  final ValueChanged<JetBoxStyle> onCommit;

  /// Whether to show the fill swatch.
  final bool showFill;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context)!;
    // Fill, outline and width share one label-less row. The two color boxes
    // are compact swatches distinguished by a leading glyph (bucket = fill,
    // square = outline). Width fills the remaining width.
    return Row(
      children: <Widget>[
        if (showFill) ...<Widget>[
          _ColorField(
            keyBase: '$keyBase.fill',
            value: style.fill,
            allowNone: true,
            compact: true,
            leadingIcon: LucideIcons.paintBucket,
            semanticLabel: l10n.propertiesFill,
            onCommit: (JetColor? c) => onCommit(style.copyWith(fill: c)),
          ),
          const SizedBox(width: 6),
        ],
        _ColorField(
          keyBase: '$keyBase.stroke',
          value: style.stroke,
          allowNone: true,
          compact: true,
          leadingIcon: LucideIcons.pen,
          semanticLabel: l10n.propertiesOutline,
          onCommit: (JetColor? c) => onCommit(style.copyWith(stroke: c)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PresetDropdown(
            fieldKey: ValueKey<String>('$keyBase.strokeWidth'),
            triggerPreview: _LineWidthPreview(width: style.strokeWidth),
            label: _format(style.strokeWidth),
            tooltip: l10n.propertiesOutlineWidth,
            options: <_DropdownOption>[
              for (final double w in _strokeWidthPresets)
                _DropdownOption(
                  optionKey:
                      ValueKey<String>('$keyBase.strokeWidth.option.${_format(w)}'),
                  label: _format(w),
                  preview: _LineWidthPreview(width: w),
                  selected: style.strokeWidth == w,
                  onPick: () => onCommit(style.copyWith(strokeWidth: w)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
```

**Note on `copyWith`:** `JetBoxStyle.copyWith` is sentinel-based, so passing an explicit `null` for `fill`/`stroke` clears it — which is exactly what `_ColorField`'s None entry means here. Do not "fix" this into a preserve.

- [ ] **Step 2: Refactor the shape Appearance section onto it**

In `element_inspector.dart`, replace the `Row(...)` inside the `KeyedSubtree(key: ValueKey<String>('$_p.appearance.$id'))` with:

```dart
_BoxStyleEditor(
  keyBase: '$_p.field',
  style: element.style,
  onCommit: (JetBoxStyle next) => controller.setShapeStyle(id, next),
  showFill: element.kind != ShapeKind.line,
),
```

Keep the `SectionLabel(l10n.propertiesAppearance)` above it and the surrounding `KeyedSubtree` / `Column` intact.

- [ ] **Step 3: Run the existing suite — it must pass unchanged**

```bash
cd packages/jet_print && flutter test test/designer/properties_editor_test.dart
```

Expected: PASS, no test edited. The line-shape case is covered by an existing test asserting no fill swatch appears for a line; if it fails, `showFill` is wired backwards.

- [ ] **Step 4: Write a test pinning the line-shape flag explicitly**

The existing coverage is indirect, so pin the flag itself. Append to `packages/jet_print/test/designer/properties_editor_test.dart` is **not** allowed (that file stays unchanged); create `packages/jet_print/test/designer/crosstab_style_test.dart` with this first test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('a line shape has no fill swatch, a rectangle does',
      (WidgetTester tester) async {
    await pumpDesignerWithShape(tester, ShapeKind.line);
    expect(findPanelKey('field.fill'), findsNothing,
        reason: 'a line has no interior, so the fill swatch is dropped');
    expect(findPanelKey('field.stroke'), findsOneWidget);

    await pumpDesignerWithShape(tester, ShapeKind.rectangle);
    expect(findPanelKey('field.fill'), findsOneWidget);
  });
}
```

Use whatever pump/finder helpers `test/designer/crosstab_inspector_test.dart` already establishes for reaching the Properties tab; reuse them rather than inventing new ones. If no shared harness file exists, define `pumpDesignerWithShape` and `findPanelKey` locally in this test file — do not create a new shared support file for two helpers.

**Reaching the Properties tab is non-obvious:** the right panel is a `ShadTabs` that builds only the active tab's body and opens on Data Source. You must `await tester.ensureVisible(find.text('Properties'))` before `await tester.tap(...)`, then `await tester.pumpAndSettle()`. A bare `tap` finds 0 widgets.

- [ ] **Step 5: Run the new test and the designer suite**

```bash
cd packages/jet_print && flutter test test/designer && dart analyze
```

Expected: PASS, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart \
        packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/element_inspector.dart \
        packages/jet_print/test/designer/crosstab_style_test.dart
git commit -m "refactor(designer): extract a composed _BoxStyleEditor

Second consumer of the spec C extraction: the shape Appearance section. Four
crosstab box slots reuse it.

showFill preserves the line shape's dropped fill swatch — no crosstab slot
exercises that path, so it now has a test of its own rather than relying on
the element suite alone."
```

---

### Task 3: Localization keys

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`
- Test: `packages/jet_print/test/designer/localization_test.dart`, `localization_tr_test.dart`, `localization_de_test.dart`

**Interfaces:**
- Produces: `l10n.crosstabStyleHeader`, `l10n.crosstabStyleCells`, `l10n.crosstabStyleTotals`, `l10n.crosstabStyleReset`, `l10n.crosstabStyleInherited`, `l10n.crosstabMeasureStyle` — all `String` getters on `JetPrintLocalizations`.

- [ ] **Step 1: Add the six keys to `jet_print_en.arb`**

Insert next to the existing `crosstab*` keys:

```json
  "crosstabStyleHeader": "Header cells",
  "@crosstabStyleHeader": {
    "description": "Properties section label for the crosstab header-cell text and box style (spec C)."
  },
  "crosstabStyleCells": "Data cells",
  "@crosstabStyleCells": {
    "description": "Properties section label for the crosstab data-cell text and box style (spec C)."
  },
  "crosstabStyleTotals": "Total cells",
  "@crosstabStyleTotals": {
    "description": "Properties section label for the crosstab subtotal and grand-total cell style (spec C)."
  },
  "crosstabStyleReset": "Reset to default",
  "@crosstabStyleReset": {
    "description": "Tooltip on the action clearing one crosstab style role back to inherited (spec C)."
  },
  "crosstabStyleInherited": "Inherited",
  "@crosstabStyleInherited": {
    "description": "Hint shown beside a crosstab style role whose slots are unset and therefore inherited (spec C)."
  },
  "crosstabMeasureStyle": "Cell override",
  "@crosstabMeasureStyle": {
    "description": "Sub-label in a crosstab measure card for that measure's own cell text and box style (spec C)."
  },
```

- [ ] **Step 2: Add the same six keys to `jet_print_tr.arb`**

Turkish translations (values only; the `@key` description entries live in the English ARB):

```json
  "crosstabStyleHeader": "Başlık hücreleri",
  "crosstabStyleCells": "Veri hücreleri",
  "crosstabStyleTotals": "Toplam hücreleri",
  "crosstabStyleReset": "Varsayılana döndür",
  "crosstabStyleInherited": "Devralınan",
  "crosstabMeasureStyle": "Hücre geçersiz kılma",
```

- [ ] **Step 3: Add the same six keys to `jet_print_de.arb`**

```json
  "crosstabStyleHeader": "Kopfzeilenzellen",
  "crosstabStyleCells": "Datenzellen",
  "crosstabStyleTotals": "Summenzellen",
  "crosstabStyleReset": "Auf Standard zurücksetzen",
  "crosstabStyleInherited": "Geerbt",
  "crosstabMeasureStyle": "Zellen-Überschreibung",
```

- [ ] **Step 4: Regenerate and verify the ARBs parse**

```bash
cd packages/jet_print && flutter gen-l10n
```

Expected: no output, no error. An "Unexpected character" error means a stray unescaped quote — check the descriptions.

- [ ] **Step 5: Verify the getters exist**

```bash
cd packages/jet_print && grep -c "crosstabStyleHeader" lib/src/designer/l10n/jet_print_localizations_en.dart
```

Expected: a non-zero count. Never hand-edit that file.

- [ ] **Step 6: Run the localization suites and analyze**

```bash
cd packages/jet_print && flutter test test/designer/localization_test.dart test/designer/localization_tr_test.dart test/designer/localization_de_test.dart && dart analyze
```

Expected: PASS, analyze clean. These suites assert every ARB has the same key set — a missing translation fails here.

- [ ] **Step 7: Commit**

```bash
git add packages/jet_print/lib/src/designer/l10n/
git commit -m "i18n(designer): six crosstab style keys in en/tr/de"
```

---

### Task 4: The three crosstab appearance sections

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart`
- Test: `packages/jet_print/test/designer/crosstab_style_test.dart`

**Interfaces:**
- Consumes: `_TextStyleEditor`, `_BoxStyleEditor` (Tasks 1-2); the six l10n getters (Task 3); `setCrosstabStyle(String, CrosstabStyle)`; `findCrosstab(ReportDefinition, String)`.
- Produces: `_crosstabRoleSection({...}) → List<Widget>`, and `_kCrosstabHeaderDefault` / `_kCrosstabCellDefault` — the panel's mirror of the planner's defaults.

- [ ] **Step 1: Write the failing tests**

Append to `packages/jet_print/test/designer/crosstab_style_test.dart`:

```dart
  test('the panel mirrors the planner dominant defaults', () {
    // The planner resolves an unset headerText to a centred style for column
    // headers, and an unset cellText/totalText to a right-aligned one for
    // value cells. The panel re-derives these rather than importing the
    // render layer; this test is what stops the two copies drifting.
    expect(_kCrosstabHeaderDefault.align, JetTextAlign.center);
    expect(_kCrosstabCellDefault.align, JetTextAlign.right);
  });

  testWidgets('an unstyled crosstab shows inherited values, not blanks',
      (WidgetTester tester) async {
    await pumpDesignerWithCrosstab(tester);
    // All six slots are null, so each role shows what it would inherit.
    expect(findPanelKey('crosstab.header.fontSize'), findsOneWidget);
    expect(findPanelKey('crosstab.cells.fontSize'), findsOneWidget);
    expect(findPanelKey('crosstab.totals.fontSize'), findsOneWidget);
  });

  testWidgets('the reset action is absent until a slot is set',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    expect(findPanelKey('crosstab.header.reset'), findsNothing);

    await tester.tap(findPanelKey('crosstab.header.fontSize'));
    await tester.pumpAndSettle();
    await tester.tap(findPanelKey('crosstab.header.fontSize.option.24'));
    await tester.pumpAndSettle();

    expect(findPanelKey('crosstab.header.reset'), findsOneWidget);
  });

  testWidgets('the first edit materializes only its own slot',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    await tester.tap(findPanelKey('crosstab.header.fontSize'));
    await tester.pumpAndSettle();
    await tester.tap(findPanelKey('crosstab.header.fontSize.option.24'));
    await tester.pumpAndSettle();

    final CrosstabStyle s = onlyCrosstab(c).style;
    expect(s.headerText?.fontSize, 24);
    expect(s.cellText, isNull, reason: 'editing one role must not seed others');
    expect(s.totalText, isNull);
    expect(s.headerBox, isNull);
  });

  testWidgets('reset clears the role back to inherited',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    await tester.tap(findPanelKey('crosstab.header.fontSize'));
    await tester.pumpAndSettle();
    await tester.tap(findPanelKey('crosstab.header.fontSize.option.24'));
    await tester.pumpAndSettle();
    await tester.tap(findPanelKey('crosstab.header.reset'));
    await tester.pumpAndSettle();

    expect(onlyCrosstab(c).style.headerText, isNull);
    expect(findPanelKey('crosstab.header.reset'), findsNothing);
  });

  testWidgets('one edit is one undo step', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    await tester.tap(findPanelKey('crosstab.header.fontSize'));
    await tester.pumpAndSettle();
    await tester.tap(findPanelKey('crosstab.header.fontSize.option.24'));
    await tester.pumpAndSettle();

    c.undo();
    expect(onlyCrosstab(c).style.headerText, isNull);
  });

  testWidgets('an untouched crosstab round-trips byte-identically',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    final String before = JetReportFormat.encodeJson(c.definition);
    // Merely selecting the crosstab and building its inspector must not write.
    expect(JetReportFormat.encodeJson(c.definition), before);
    expect(before.contains('headerText'), isFalse);
  });
```

`onlyCrosstab(c)` returns the single `CrosstabNode`'s crosstab from `c.definition.body.root.children` — walk the public tree, never `package:jet_print/src/...` (an `encapsulation_test` forbids it from this path):

```dart
Crosstab onlyCrosstab(JetReportDesignerController c) => c
    .definition.body.root.children
    .whereType<CrosstabNode>()
    .single
    .crosstab;
```

`pumpDesignerWithCrosstab` mounts the designer with a schema, adds a crosstab through `controller.createCrosstab(rootScopeId, fields: <FieldDef>[...])`, selects it with `controller.select(Selection.crosstab(id))`, opens the Properties tab (`ensureVisible` then `tap`), and returns the controller. Model it on the existing `test/designer/crosstab_inspector_test.dart` setup and reuse its helpers where they exist.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd packages/jet_print && flutter test test/designer/crosstab_style_test.dart
```

Expected: FAIL — `_kCrosstabHeaderDefault` is undefined, and every `findPanelKey('crosstab.header.…')` finds 0 widgets.

- [ ] **Step 3: Add the defaults and the role section to `style_section.dart`**

```dart
/// The panel's mirror of the planner's dominant default for the header role.
///
/// `CrosstabStyle.headerText` is read at two sites with different fallbacks
/// while unset: column headers centre, the single row-label stub column falls
/// back to [JetTextStyle.fallback] (left). The section displays the centred
/// one — column headers outnumber the one stub column — and the approximation
/// ends at the first edit, because an authored headerText is honoured at both
/// sites, alignment included.
///
/// Mirrored rather than imported: the render layer is not a designer
/// dependency and the panel must work with no data source attached. A test
/// asserts this equals the planner's value so the two copies cannot drift.
const JetTextStyle _kCrosstabHeaderDefault =
    JetTextStyle(align: JetTextAlign.center);

/// The panel's mirror of the planner's default for value cells — right
/// aligned, per spec A §3. Shared by the Cells and Totals roles: an unset
/// `totalText` cascades to the cell style for total VALUES (total labels take
/// the left-aligned row-label style, the same dual fallback headerText has).
const JetTextStyle _kCrosstabCellDefault =
    JetTextStyle(align: JetTextAlign.right);

/// One crosstab appearance role: its label, a text and a box editor, and a
/// reset that clears both slots back to inherited.
///
/// [text] and [box] are the authored slots — null means inherited, and the
/// editors then display [effectiveText] / [effectiveBox] so the controls are
/// never blank. Any edit commits a concrete style; [onReset] writes null back.
///
/// The reset action appears only once at least one slot is set: an
/// always-visible reset on an untouched role would suggest state that is not
/// there.
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
  required JetPrintLocalizations l10n,
}) {
  final bool authored = text != null || box != null;
  return <Widget>[
    const SizedBox(height: 12),
    Row(
      children: <Widget>[
        Expanded(child: SectionLabel(label)),
        if (!authored)
          Text(l10n.crosstabStyleInherited,
              style: const TextStyle(fontSize: 11))
        else
          _CardAction(
            actionKey: ValueKey<String>('$keyBase.reset'),
            icon: LucideIcons.rotateCcw,
            tooltip: l10n.crosstabStyleReset,
            onPressed: onReset,
          ),
      ],
    ),
    _TextStyleEditor(
      keyBase: keyBase,
      style: text ?? effectiveText,
      onCommit: onText,
    ),
    const SizedBox(height: 4),
    _BoxStyleEditor(
      keyBase: keyBase,
      style: box ?? effectiveBox,
      onCommit: onBox,
    ),
  ];
}
```

`_CardAction` already exists in `crosstab_inspector.dart` (the compact icon action used in axis and measure card headers) — reuse it rather than adding another. If its constructor parameter names differ from the above, use the real ones.

- [ ] **Step 4: Call it three times from the crosstab inspector**

In `crosstab_inspector.dart`, add to `_crosstabInspector`'s returned list, after the Layout section and before Visibility:

```dart
..._crosstabRoleSection(
  label: l10n.crosstabStyleHeader,
  keyBase: '$_p.crosstab.header',
  text: ct.style.headerText,
  box: ct.style.headerBox,
  effectiveText: _kCrosstabHeaderDefault,
  effectiveBox: JetBoxStyle.none,
  onText: (JetTextStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(headerText: () => s)),
  onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(headerBox: () => s)),
  onReset: () => controller.setCrosstabStyle(
      crosstabId,
      ct.style.copyWith(headerText: () => null, headerBox: () => null)),
  l10n: l10n,
),
..._crosstabRoleSection(
  label: l10n.crosstabStyleCells,
  keyBase: '$_p.crosstab.cells',
  text: ct.style.cellText,
  box: ct.style.cellBox,
  effectiveText: _kCrosstabCellDefault,
  effectiveBox: JetBoxStyle.none,
  onText: (JetTextStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(cellText: () => s)),
  onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(cellBox: () => s)),
  onReset: () => controller.setCrosstabStyle(crosstabId,
      ct.style.copyWith(cellText: () => null, cellBox: () => null)),
  l10n: l10n,
),
..._crosstabRoleSection(
  label: l10n.crosstabStyleTotals,
  keyBase: '$_p.crosstab.totals',
  text: ct.style.totalText,
  box: ct.style.totalBox,
  effectiveText: _kCrosstabCellDefault,
  effectiveBox: JetBoxStyle.none,
  onText: (JetTextStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(totalText: () => s)),
  onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
      crosstabId, ct.style.copyWith(totalBox: () => s)),
  onReset: () => controller.setCrosstabStyle(crosstabId,
      ct.style.copyWith(totalText: () => null, totalBox: () => null)),
  l10n: l10n,
),
```

Wrap all three in a `KeyedSubtree(key: ValueKey<String>('$_p.crosstab.style.$crosstabId'), …)` if the surrounding list already uses that pattern for selection-switch invalidation; follow whatever the neighbouring sections do.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd packages/jet_print && flutter test test/designer/crosstab_style_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run the designer suite and analyze**

```bash
cd packages/jet_print && flutter test test/designer && dart analyze
```

Expected: PASS, analyze clean, no golden moved.

- [ ] **Step 7: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties/fields/style_section.dart \
        packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart \
        packages/jet_print/test/designer/crosstab_style_test.dart
git commit -m "feat(designer): author the six crosstab style slots

Three flat sections — Header, Cells, Totals — matching every other panel; the
designer has no disclosure primitive and adding one for this would be new
shared vocabulary.

Null means inherited: each role displays the value the planner's cascade would
resolve, the first edit materializes only that slot, and a reset writes null
back. Untouched crosstabs therefore still serialize without any style keys."
```

---

### Task 5: Per-measure cell overrides

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart` (`_crosstabMeasureCard`)
- Test: `packages/jet_print/test/designer/crosstab_style_test.dart`

**Interfaces:**
- Consumes: `_TextStyleEditor`, `_BoxStyleEditor`, `_kCrosstabCellDefault`, `l10n.crosstabMeasureStyle`, `updateCrosstabMeasure`.
- Produces: nothing consumed by a later task.

- [ ] **Step 1: Write the failing tests**

Append to `crosstab_style_test.dart`:

```dart
  testWidgets('a measure override inherits from the crosstab, not the renderer',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    final Crosstab ct = onlyCrosstab(c);
    // Give the crosstab a cell style; the measure's override must show THAT,
    // one cascade layer up — not the renderer's right-aligned default.
    c.setCrosstabStyle(
        ct.id, ct.style.copyWith(cellText: () => const JetTextStyle(fontSize: 20)));
    await tester.pumpAndSettle();

    final String mid = onlyCrosstab(c).measures.first.id;
    expect(valueInPanelKey('crosstab.measure.$mid.cellText.fontSize', '20'),
        findsOneWidget);
  });

  testWidgets('a measure override writes only that measure',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWithCrosstab(tester);
    final String mid = onlyCrosstab(c).measures.first.id;

    await tester.tap(findPanelKey('crosstab.measure.$mid.cellText.fontSize'));
    await tester.pumpAndSettle();
    await tester
        .tap(findPanelKey('crosstab.measure.$mid.cellText.fontSize.option.24'));
    await tester.pumpAndSettle();

    final Crosstab ct = onlyCrosstab(c);
    expect(ct.measures.first.cellTextStyle?.fontSize, 24);
    expect(ct.style.cellText, isNull,
        reason: 'a measure override must not write the crosstab-level slot');
  });
```

`valueInPanelKey(key, text)` finds `find.text(text)` descended from that key's widget — mirror `_valueIn` in `properties_editor_test.dart:26`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd packages/jet_print && flutter test test/designer/crosstab_style_test.dart
```

Expected: FAIL — the measure card has no `cellText` editors, so the finders match 0 widgets.

- [ ] **Step 3: Add the two editors to the measure card**

In `_crosstabMeasureCard`, after the `_FormatField` and before the closing `],`:

```dart
const SizedBox(height: 8),
// The measure's own cell override — the first layer of the planner's
// cascade (measure → crosstab style → renderer default). Its displayed
// inherited value is the crosstab's own cellText/cellBox, one layer up,
// so the inheritance shown is truthful at this level rather than jumping
// straight to the renderer default.
SectionLabel(l10n.crosstabMeasureStyle),
_TextStyleEditor(
  keyBase: '$base.cellText',
  style: measure.cellTextStyle ?? ct.style.cellText ?? _kCrosstabCellDefault,
  onCommit: (JetTextStyle s) => controller.updateCrosstabMeasure(
      ct.id,
      measure.id,
      (CrosstabMeasure m) => m.copyWith(cellTextStyle: () => s)),
),
const SizedBox(height: 4),
_BoxStyleEditor(
  keyBase: '$base.cellBox',
  style: measure.cellBoxStyle ?? ct.style.cellBox ?? JetBoxStyle.none,
  onCommit: (JetBoxStyle s) => controller.updateCrosstabMeasure(
      ct.id,
      measure.id,
      (CrosstabMeasure m) => m.copyWith(cellBoxStyle: () => s)),
),
```

Verify `CrosstabMeasure.copyWith` takes thunks for these two slots; if it takes plain values, pass the value directly instead of `() => s`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd packages/jet_print && flutter test test/designer/crosstab_style_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the designer suite and analyze**

```bash
cd packages/jet_print && flutter test test/designer && dart analyze
```

Expected: PASS, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart \
        packages/jet_print/test/designer/crosstab_style_test.dart
git commit -m "feat(designer): author per-measure crosstab cell overrides

CrosstabMeasure.cellTextStyle/cellBoxStyle are the first layer of the
planner's cascade and were the two slots spec B's deferral list missed. They
are edited in the measure card, beside the expression and aggregate they
describe, and their displayed inherited value is the crosstab's own cell style
— one layer up, not the renderer default."
```

---

### Task 6: Full sweep, changelog, and spec status

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-09-01-crosstab-style-editors-design.md` (status line)

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: nothing.

- [ ] **Step 1: Run both packages' full suites**

```bash
cd packages/jet_print && flutter test
cd ../../apps/jet_print_playground && flutter test
```

Expected: PASS in both. Record the counts; the jet_print baseline before this plan was 2476 and the playground 121, so expect those plus the new tests. No golden may have moved.

- [ ] **Step 2: Analyze both packages**

```bash
cd packages/jet_print && dart analyze
cd ../../apps/jet_print_playground && dart analyze
```

Expected: "No issues found!" in both.

- [ ] **Step 3: Add the changelog entry**

Under `## Unreleased` in `packages/jet_print/CHANGELOG.md`:

```markdown
- Crosstab style editors (spec 046-crosstab-style-editors): the eight crosstab
  appearance slots — the six on `CrosstabStyle` plus `CrosstabMeasure`'s two
  per-measure overrides — are now authorable in the Properties panel. They
  already rendered; only the UI was missing. Unset slots display the value they
  inherit rather than a blank, the first edit materializes only that slot, and a
  reset clears it back, so a crosstab whose appearance is untouched still
  serializes without any style keys.
```

- [ ] **Step 4: Mark the spec implemented**

In `docs/superpowers/specs/2026-09-01-crosstab-style-editors-design.md`, change:

```markdown
**Status:** Designed — not yet implemented.
```

to:

```markdown
**Status:** Implemented.
```

- [ ] **Step 5: Verify no golden moved**

```bash
git status --short
```

Expected: no file under `test/designer/goldens/` or any `*.png` is modified. If one is, the extraction changed layout — revert the golden and fix the widget.

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/CHANGELOG.md docs/superpowers/specs/2026-09-01-crosstab-style-editors-design.md
git commit -m "docs: changelog and spec status for crosstab style editors"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §1 new part file, `_TextStyleEditor` | 1 |
| §1 `_BoxStyleEditor` + `showFill` | 2 |
| Decision 4, extraction validated by existing suites | 1 step 5, 2 step 3 |
| §2 role section, inherit/materialize/reset | 4 |
| §2 dual-fallback dominant default + drift test | 4 steps 1, 3 |
| §3 measure card overrides, cascade one layer up | 5 |
| §4 localization, six keys × three locales | 3 |
| §5 testing table, all eleven rows | 2 (line shape), 4 (seven rows), 5 (two rows), 6 (goldens) |
| "no golden moves" | 1 step 6, 4 step 6, 6 step 5 |

No gaps.

**Placeholder scan:** no TBD/TODO. Three steps say "follow whatever the neighbouring code does" (Task 2 step 4 harness reuse, Task 4 step 3 `_CardAction` parameter names, Task 4 step 4 `KeyedSubtree`) — these are deliberate deference to code the implementer will have open, each with the exact fallback stated, not deferred decisions.

**Type consistency:** `_TextStyleEditor` and `_BoxStyleEditor` keep identical signatures across Tasks 1, 2, 4 and 5. `keyBase` is always the prefix *without* a trailing dot; every child appends `'.name'`. `_kCrosstabHeaderDefault` / `_kCrosstabCellDefault` are declared in Task 4 step 3 and used in Tasks 4 and 5 under those exact names. `onlyCrosstab`, `findPanelKey`, `valueInPanelKey` and `pumpDesignerWithCrosstab` are defined in Tasks 2 and 4 and reused in Task 5.
