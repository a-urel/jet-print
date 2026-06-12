# Data Model: Format Properties — Font & Color Editors

**Feature**: `021-format-properties` | **Date**: 2026-06-13
**Sources**: [spec.md](spec.md) Key Entities · [research.md](research.md) decisions 1–10

## 1. `JetTextStyle` — extended (domain, public)

File: `packages/jet_print/lib/src/domain/styles/text_style.dart`

| Field | Type | Default | Change |
|---|---|---|---|
| `fontFamily` | `String?` | `null` (= renderer default) | unchanged |
| `fontSize` | `double` | `12` | unchanged |
| `weight` | `JetFontWeight` | `normal` | unchanged (enum keeps all 4 values) |
| `italic` | `bool` | `false` | unchanged |
| **`underline`** | `bool` | `false` | **NEW** — additive |
| `color` | `JetColor` | `JetColor.black` | unchanged |
| `align` | `JetTextAlign` | `left` | unchanged |

**New API**:

```dart
JetTextStyle copyWith({
  Object? fontFamily = _unset, // sentinel: omitted ≠ set-to-null
  double? fontSize,
  JetFontWeight? weight,
  bool? italic,
  bool? underline,
  JetColor? color,
  JetTextAlign? align,
})
```

- `==`/`hashCode`/`toString` extended with `underline`.
- **Validation** (enforced by the editors, not the model — the model stays a dumb value):
  `fontSize` clamped to **4–144 pt** (FR-002).

**Serialization** (`toJson`/`fromJson` in the same file):
- `underline` written **only when `true`**; missing/non-bool on load ⇒ `false`.
- All existing keys and omission rules unchanged (`fontFamily` omitted when null; whole
  `style` omitted by `TextElementCodec` when `== JetTextStyle.fallback` — a style that is
  fallback-plus-underline is no longer equal to fallback, so it serializes).

## 2. `JetBoxStyle` — extended (domain, public)

File: `packages/jet_print/lib/src/domain/styles/box_style.dart`

| Field | Type | Default | Semantics |
|---|---|---|---|
| `fill` | `JetColor?` | `null` | `null` = **no fill** (FR-007) |
| `stroke` | `JetColor?` | `null` | `null` = **no outline** (FR-008) |
| `strokeWidth` | `double` | `1.0` | clamped by editor to **0–20 pt**; `0` ⇒ outline not rendered, `stroke` color retained (research §6) |

**New API**:

```dart
JetBoxStyle copyWith({
  Object? fill = _unset,   // sentinel: explicit null = "no fill"
  Object? stroke = _unset, // sentinel: explicit null = "no outline"
  double? strokeWidth,
})
```

No serialization change (fields already exist; `null` already omitted on write, missing ⇒
`null` on read).

## 3. `JetColor` — unchanged

`int argb` packed `0xAARRGGBB`; JSON `#AARRGGBB` uppercase (`color.dart`). The editor layer
adds *no* model change; hex parsing/formatting for the editor lives in the designer widget
(display `#RRGGBB` when alpha `FF`, else `#AARRGGBB`; input regex
`^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$`; 6-digit input preserves stored alpha — research §5).

## 4. Edit commands (designer, private)

Directory: `packages/jet_print/lib/src/designer/controller/commands/`

| Command | Fields | `apply` semantics |
|---|---|---|
| `SetTextStyleCommand` | `id`, `JetTextStyle style` | Replace the `TextElement`'s `style`. Returns `before` when target missing, not a `TextElement`, or `style == current` (no history, no notify). Label: `'Edit text style'`. |
| `SetShapeStyleCommand` | `id`, `JetBoxStyle style` | Replace the `ShapeElement`'s `style`. Same no-op rules. Label: `'Edit shape style'`. |
| `SetBarcodeColorCommand` | `id`, `JetColor color` | Replace the `BarcodeElement`'s `color`. Same no-op rules. Label: `'Edit barcode color'`. |

All three are pure `DesignerDocument → DesignerDocument` transforms through the existing
`_commit` path (`jet_report_designer_controller.dart:986`): one committed editor change =
one history entry (FR-013).

**Controller mutators** (public, on `JetReportDesignerController`):

```dart
void setTextStyle(String id, JetTextStyle style);
void setShapeStyle(String id, JetBoxStyle style);
void setBarcodeColor(String id, JetColor color);
```

Element `copyWith` support: `TextElement.copyWith(style: …)` exists; verify/extend
`ShapeElement.copyWith(style: …)` (exists since 020) and add `BarcodeElement.copyWith`
(color) if absent.

## 5. Font availability surface (rendering → designer, internal)

File: `packages/jet_print/lib/src/rendering/text/font_registry.dart`

```dart
/// Registered family names, default family first, then insertion order, deduped.
List<String> get families;
```

Wiring: the single `FontRegistry` (today `FontRegistry()..registerDefault()`) is hoisted
from `DesignCanvas` (`design_canvas.dart:91`) into the designer state and handed to both the
`DesignTimeFrameBuilder` and the Properties panel. **Not** exported publicly (research §1).

**Family picker view-model** (computed in the panel):

| State | Picker shows |
|---|---|
| `style.fontFamily == null` | default family (`JetSans`) selected |
| family registered | that family selected, rendered in its own typeface |
| family **not** registered | stored name appended, selected, marked unavailable; rendering falls back via existing `resolveFamily` chain; value preserved until user picks another family |

## 6. Underline geometry helper (rendering, internal)

File: `packages/jet_print/lib/src/rendering/text/underline_metrics.dart` (NEW)

```dart
/// Shared underline geometry so canvas and PDF draw identical lines (IV).
({double offset, double thickness}) underlineFor(double fontSize);
// offset ≈ 0.11 × fontSize below baseline; thickness ≈ 0.06 × fontSize
```

Consumed by `CanvasPainter.drawTextRun` and `PdfPainter.drawTextRun` inside their existing
per-line alignment math; the drawn segment spans the measured line width at the aligned `dx`.

## 7. Renderer delta (rendering, internal)

`ShapeElementRenderer.emit`: rect/path/line emission passes
`stroke: el.style.strokeWidth > 0 ? el.style.stroke : null` (research §6).
`BarcodeElementRenderer`: placeholder primitives tinted with `el.color` (research §8).

## 8. State transitions (editor ↔ model)

```
[element selected] → panel reads current style → editors display effective values
  typed field (size, hex, width): focus → edit → Enter/blur
      valid   → clamp → copyWith → controller op → _commit → canvas repaint ≤100ms
      invalid → reject, restore last valid, visual feedback, NO commit
  picker/toggle/swatch/segment/None: click → copyWith → controller op → _commit
  no-op commit (same value) → command returns `before` → no history entry
[selection changes mid-edit] → widget state rebuilt → uncommitted input discarded
[undo/redo] → document snapshot restored → panel re-reads style (values + toggles reflect)
```

## 9. Schema impact

**None.** `kReportSchemaVersion` stays **1**; `underline` is additive-optional under the
pre-1.0 carve-out (`report_codec.dart:18-22`). Pre-feature JSON loads unchanged and
re-serializes byte-identically (omission rules intact). No migration entry.
