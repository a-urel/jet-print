# Watermark Designer UI — Design

**Date:** 2026-06-28
**Branch:** `043-watermark-support` (continues the watermark engine feature)
**Status:** Approved design, pending implementation plan.

## Goal

Let an author set a **text watermark** on a report from the visual designer — in the **report-root Properties panel** (shown when the whole report/page is selected). Editing text, color, font size, opacity, and angle updates `definition.furniture.watermark` through one undoable command, and the canvas/draft preview reflects it live (WYSIWYG).

This is the deferred phase-2 UI from the watermark engine design (`2026-06-28-watermark-support-design.md`). The model, render, and serialization all already ship; this adds **only** designer authoring.

Out of scope for this slice: authoring **image** watermarks (the designer has no image-bytes picker — `ImageElement` authors images via field binding, not raw bytes; building a file-picker is a separate, larger piece). An image watermark loaded from JSON is preserved and partially editable (see Edge Cases), never silently dropped.

## Decisions (locked)

- **Text watermark only** in the UI. Image watermarks remain API/JSON-authored.
- **Enable toggle** (`ShadSwitch`) gates the section: off ⇒ `watermark = null`; on ⇒ a default `Watermark(text: <localized "DRAFT">, textStyle: JetTextStyle(fontSize: 64))` so something renders immediately. **The default MUST set a large `fontSize`** — `JetTextStyle.fallback` is 12pt and the engine draws text at literal size (no page-scaling), so a 12pt watermark on A4 is a near-invisible dot. 64 matches the scale of the engine's watermark goldens (56–80).
- **Knobs:** text, color, font size, opacity (0–1), angle (degrees). Dropped: font family, italic, underline, align — irrelevant for a centered watermark.
- Each edit commits a **whole new `Watermark`** via one command = one undo step (mirrors how `setTextStyle` commits a whole `copyWith`).
- Designer-only: no domain/render/serialization change.

## Architecture

```
Properties panel (report root selected)
  └─ _watermarkSection()  ── reads definition.furniture.watermark
        │  edit (text/color/size/opacity/angle/toggle)
        ▼
  JetReportDesignerController.setWatermark(Watermark?)
        ▼
  _commit(SetWatermarkCommand(wm))   ── undo/redo + notifyListeners
        ▼
  DesignerDocument.withDefinition(def.copyWith(furniture: <fresh PageFurniture>))
        ▼
  canvas + draft preview rebuild → watermark renders live (existing engine path)
```

No engine/model/serialization change. The watermark renders through the already-shipped `buildWatermarkPrimitive` → `paintFrame` path the moment the definition changes.

## Components

### 1. `SetWatermarkCommand` — new

`lib/src/designer/controller/commands/set_watermark_command.dart`, extends `EditCommand` (mirrors `SetPageFormatCommand`).

```dart
class SetWatermarkCommand extends EditCommand {
  const SetWatermarkCommand(this.watermark);
  final Watermark? watermark; // null clears

  @override
  String get label => 'Set watermark';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final PageFurniture f = before.definition.furniture;
    if (f.watermark == watermark) return before; // no-op guard
    // PageFurniture.copyWith CANNOT null-out watermark (set-only, by design),
    // so construct a fresh furniture with every slot explicit to support clearing.
    final PageFurniture next = PageFurniture(
      pageHeader: f.pageHeader,
      pageFooter: f.pageFooter,
      columnHeader: f.columnHeader,
      columnFooter: f.columnFooter,
      background: f.background,
      watermark: watermark,
    );
    return before.withDefinition(before.definition.copyWith(furniture: next));
  }
}
```

**Why a fresh `PageFurniture`, not `copyWith`:** `PageFurniture.copyWith(watermark: null)` preserves the old value (the documented set-only limitation), so it cannot clear. Explicit construction is required for the toggle-off path.

### 2. `JetReportDesignerController.setWatermark(Watermark?)` — new

Mirrors `setPageFormat`:

```dart
void setWatermark(Watermark? watermark) => _commit(SetWatermarkCommand(watermark));
```

### 3. `_watermarkSection()` — new, in `_PropertiesPanelState`

`lib/src/designer/layout/panels/properties_panel.dart`. Appended inside `_reportInspector()` after the margins block (after ~line 1606), preceded by a gap. Reads `controller.definition.furniture.watermark`.

Layout:
- `SectionLabel(l10n.propertiesWatermark)`.
- **Enable toggle** (`ShadSwitch`, label `l10n.watermarkEnable`): off → `controller.setWatermark(null)`; on → `controller.setWatermark(Watermark(text: l10n.watermarkDefaultText, textStyle: const JetTextStyle(fontSize: 64)))` (large default size — see Decisions).
- When `watermark != null` AND it is a **text** watermark (or freshly enabled), show editors. Each reads the current `Watermark wm` and commits `controller.setWatermark(wm.copyWith(...))`:
  - **Text** — `_TextInput` → `wm.copyWith(text: v)`.
  - **Color** — `_ColorField` (full, not compact) → `wm.copyWith(textStyle: wm.textStyle.copyWith(color: v))`. Note its real API: `_ColorField(keyBase: '$_p.field.watermarkColor', value: wm.textStyle.color, onCommit: (JetColor? v) {...})` — `keyBase` is a `String`, `onCommit` is `ValueChanged<JetColor?>` (the None entry can emit null; here `allowNone` stays false so color is always set).
  - **Font size** — `_NumberField` → `wm.copyWith(textStyle: wm.textStyle.copyWith(fontSize: v))`.
  - **Opacity** — `_NumberField` (0–1; clamp lives in the `Watermark` ctor) → `wm.copyWith(opacity: v)`.
  - **Angle°** — `_NumberField` → `wm.copyWith(angleDegrees: v)`.
- Field keys follow the panel convention `'$_p.field.<name>'` (e.g. `watermarkText`, `watermarkOpacity`) so tests can find them.

### 4. l10n keys — new

Added to **all three** ARB files (`jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`) with `@`-descriptions, then regenerated. (The chart feature hit a drift bug where keys existed only in generated Dart, not the ARBs — add to ARBs first.)

| key | en value |
|---|---|
| `propertiesWatermark` | Watermark |
| `watermarkEnable` | Enable |
| `watermarkText` | Text |
| `watermarkColor` | Color |
| `watermarkFontSize` | Font size |
| `watermarkOpacity` | Opacity |
| `watermarkAngle` | Angle |
| `watermarkDefaultText` | DRAFT |
| `watermarkImageExternal` | Image watermark (set outside the designer) |

## Data flow

Author selects the report root (`selection.isReport`) → panel renders `_watermarkSection()` → an edit calls `controller.setWatermark(newWm)` → `SetWatermarkCommand.apply` builds a fresh furniture and a new definition → `notifyListeners()` → canvas + draft preview re-render the watermark; the panel re-reads from `controller.definition`. Undo/redo are automatic (command pipeline).

## Edge cases

- **Image watermark loaded from JSON** (`imageBytes != null`, `text == null`): the section shows a read-only `watermarkImageExternal` row plus still-editable **opacity** and **angle** (both apply to images too), and the enable toggle still clears it. Image bytes are never dropped by a text edit — text editors are hidden in this state. (If both text and image are somehow set, the model already resolves "text wins" at render; the panel treats it as a text watermark.)
- **Empty text:** allowed; renders nothing (engine no-ops on empty/whitespace). Not an error.
- **Toggle off then undo:** `setWatermark(null)` is one undoable step; undo restores the prior watermark intact.
- **Image watermark, toggle off then on:** toggling off clears it (`null`); toggling on creates the **default text** watermark (`fontSize: 64`) — the image is not restored by re-enabling (it was cleared). The two steps are separately undoable, so `undo` twice brings the image watermark back. The image is only lost if the author keeps the text watermark and saves.
- **Opacity out of range / angle any value:** opacity is clamped in the `Watermark` constructor; angle is unrestricted.

## Testing

Widget tests mirroring `test/designer/properties_editor_test.dart` (the `pumpDesignerWith` + `selectReport` + edit-field + assert-model + undo harness):

- Report root selected → the Watermark section is present; a band/element selection does **not** show it.
- Toggle on → `definition.furniture.watermark` is non-null with the default text; toggle off → null.
- Edit text → `watermark.text` updates; edit opacity → `watermark.opacity` updates; edit angle → `watermark.angleDegrees` updates; edit color/size → `watermark.textStyle` updates.
- Each edit is one undoable step (`canUndo`; `undo()` restores prior value).
- (Edge) A definition seeded with an image watermark shows the read-only external-image row and keeps `imageBytes` after an opacity edit.

These are pure widget tests (no golden) — the canvas already has watermark goldens from the engine slice. `flutter analyze` + `dart format` clean; full designer suite green.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — one public controller method (`setWatermark`); section is designer-internal. |
| II. Layered architecture | PASS — designer → domain only; command mutates the immutable definition; no render/serialization touched. |
| III. Test-First | PASS — widget tests Red→Green per editor. |
| IV. Rendering fidelity / WYSIWYG | PASS — author-time only; the existing render path draws the watermark; no goldens change for unrelated fixtures. |
| V. Serialization | PASS — no model/codec change (uses shipped `Watermark`/`furniture` codec). |
| VI. Docs/DX | PASS — dartdoc on the command + controller method; l10n in all locales; `dart format` + clean analyzer. |

## Follow-ups (not in this slice)

- Image-watermark authoring (a designer file-picker → `Uint8List`).
- A small in-panel watermark preview swatch (today the live canvas/draft is the preview).
- Bold/weight toggle if authors want heavier watermark text.
