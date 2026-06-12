# Phase 1 Data Model: Shape Gallery in Properties Pane

Entities, the one new command, the geometry table, and the (non-)serialization impact. Dependencies
point inward: the domain gains only additive value-type changes; geometry lives in rendering; the
command/gallery live in the designer seam.

## 1. `ShapeKind` (domain enum — EXTENDED)

`lib/src/domain/elements/shape_element.dart`

```dart
enum ShapeKind {
  line,        // existing — special-cased renderer (LinePrimitive)
  rectangle,   // existing — special-cased renderer (RectPrimitive)
  ellipse,     // NEW — 64-segment inscribed polygon
  triangle,    // NEW — apex top-center, base on bottom edge
  diamond,     // NEW — four edge midpoints
  pentagon,    // NEW — regular, point-up, inscribed
  hexagon,     // NEW — regular, inscribed
  star,        // NEW — 5-point, point-up, inner/outer 0.5
}
```

- Additive only; serialized by `.name`, identical mechanism to the existing two.
- The exhaustive `switch (el.kind)` in `ShapeElementRenderer.emit` and the codec parse force every value
  to be handled (compile-time safety).

## 2. `ShapeElement` (domain — EXTENDED)

```dart
class ShapeElement extends ReportElement {
  const ShapeElement({
    required super.id,
    required super.bounds,
    required this.kind,
    this.style = JetBoxStyle.none,
    this.flipDiagonal = false,
    this.unknownForm,            // NEW
  });

  final ShapeKind kind;
  final JetBoxStyle style;
  final bool flipDiagonal;       // line-only
  final String? unknownForm;     // NEW: original serialized form name when kind was unrecognized on load

  ShapeElement copyWith({        // NEW
    JetRect? bounds,
    ShapeKind? kind,
    JetBoxStyle? style,
    bool? flipDiagonal,
    bool clearUnknownForm = false,   // explicit flag — copyWith cannot pass null to clear a nullable
  });

  // withBounds, ==, hashCode, toString — UPDATED to include unknownForm
}
```

- **Invariant**: `unknownForm` is non-null only when `kind == rectangle` and the element came from an
  unrecognized serialized form. A deliberate gallery pick clears it.
- `copyWith` uses an explicit `clearUnknownForm` flag because Dart `copyWith` cannot distinguish
  "leave unknownForm" from "set it to null" via the parameter alone.
- Equality/hashCode/`withBounds`/`toString` extended to carry `unknownForm` through.

## 3. `shape_element_codec.dart` (serialization — CHANGED, schema unchanged)

```dart
// fromJson — tolerant parse
final String raw = json['kind']! as String;
final ShapeKind? known = ShapeKind.values
    .where((k) => k.name == raw).firstOrNull;     // or values.asNameMap()[raw]
return ShapeElement(
  id: ...,
  bounds: ...,
  kind: known ?? ShapeKind.rectangle,             // safe render default
  style: ...,
  flipDiagonal: ...,
  unknownForm: known == null ? raw : null,        // preserve the original name
);

// toJson — write the preserved form back when present
'kind': element.unknownForm ?? element.kind.name,
```

- **No `kReportSchemaVersion` change** (stays `1`), no migration. Known forms are wire-identical.
- **Round-trip truth table**:

  | Serialized `kind` | This version recognizes? | Loaded `kind` | Loaded `unknownForm` | Re-serialized `kind` |
  |-------------------|--------------------------|---------------|----------------------|----------------------|
  | `rectangle`       | yes                      | rectangle     | null                 | `rectangle`          |
  | `hexagon`         | yes                      | hexagon       | null                 | `hexagon`            |
  | `octagon` (future)| no                       | rectangle     | `octagon`            | `octagon` (lossless) |
  | `octagon`, then user picks `star` | — | star | null (cleared)       | `star`               |

## 4. `shapePath(ShapeKind, JetRect) → List<PathCommand>` (rendering — NEW, private)

`lib/src/rendering/elements/shape_path.dart`

- Pure function; produces a **closed** polygon (`MoveTo` … `LineTo` … `ClosePath`) inscribed in
  `bounds`. Used by the renderer (export/preview/canvas) **and** the gallery thumbnail.
- Per-form vertex generation (cx, cy = bounds center; rx, ry = bounds half-extents):

  | Form | Vertices |
  |------|----------|
  | ellipse | 64 points at `(cx + rx·cos θ, cy + ry·sin θ)`, θ = 0…2π |
  | triangle | `(cx, top)`, `(right, bottom)`, `(left, bottom)` |
  | diamond | `(cx, top)`, `(right, cy)`, `(cx, bottom)`, `(left, cy)` |
  | pentagon | 5 points on the inscribed ellipse, point-up (−90° start), 72° step |
  | hexagon | 6 points on the inscribed ellipse, point-up, 60° step |
  | star | 10 points alternating outer (rx,ry) / inner (0.5·rx, 0.5·ry), point-up, 36° step |

- `line` / `rectangle` are **not** routed through `shapePath` — the renderer keeps their existing
  `LinePrimitive` / `RectPrimitive` special cases (the gallery thumbnails for those two draw the
  corresponding diagonal / box directly).
- **Degenerate-safe**: a 1×1 or 1×N box yields a valid (collapsed) closed path; never throws.
- `const int kEllipseSegments = 64;` — the single tunable from research D2.

## 5. `ShapeElementRenderer.emit` (rendering — CHANGED)

```dart
switch (el.kind) {
  case ShapeKind.rectangle: out.add(RectPrimitive(...));   // unchanged
  case ShapeKind.line:      out.add(LinePrimitive(...));   // unchanged
  case ShapeKind.ellipse:
  case ShapeKind.triangle:
  case ShapeKind.diamond:
  case ShapeKind.pentagon:
  case ShapeKind.hexagon:
  case ShapeKind.star:
    out.add(PathPrimitive(
      bounds: bounds,
      commands: shapePath(el.kind, bounds),
      fill: el.style.fill,
      stroke: el.style.stroke,
      strokeWidth: el.style.strokeWidth,
      elementId: el.id,
    ));
}
```

## 6. `SetShapeKindCommand` (designer — NEW, private)

`lib/src/designer/controller/commands/set_shape_kind_command.dart`

```dart
class SetShapeKindCommand extends EditCommand {
  const SetShapeKindCommand({required this.id, required this.kind});
  final String id;
  final ShapeKind kind;

  @override
  String get label => 'Set shape';

  @override
  DesignerDocument apply(DesignerDocument before) {
    // locate the ShapeElement with this id;
    // if its kind == kind AND unknownForm == null → return before (no-op, FR-005);
    // else replace it with:
    //   element.copyWith(
    //     kind: kind,
    //     flipDiagonal: kind == ShapeKind.line ? element.flipDiagonal : false,
    //     clearUnknownForm: true,
    //   )
  }
}
```

- Returns `before` unchanged on no-op so `_commit`'s identity check records no history / no notify.
- One command = one undo step (FR-006); `redo` is the existing history mirror.

## 7. Controller op (designer — NEW)

`jet_report_designer_controller.dart`

```dart
/// Changes the form of the shape [id] to [kind] as one undoable step.
/// A no-op (already that form) records no history. Switching off a line
/// resets the line-only diagonal flip; a deliberate pick clears any
/// preserved unrecognized form name.
void setShapeKind(String id, ShapeKind kind) =>
    _commit(SetShapeKindCommand(id: id, kind: kind));
```

## 8. Designer UI (designer — NEW, private)

`properties_panel.dart`

- In `_elementInspector`, after the geometry sections:
  `if (element is ShapeElement) ...[ SectionLabel(l10n.propertiesShape), _ShapeGallery(...) ]`.
- `_ShapeGallery`: a wrap/grid of eight `_ShapeThumbnail`s; the one matching `element.kind` (and only
  when `unknownForm == null`) is highlighted; tapping a non-active one calls
  `controller.setShapeKind(element.id, kind)`.
- `_ShapeThumbnail`: a `CustomPaint` drawing `shapePath(kind, thumbRect)` (or the line/rect special
  case), wrapped in `Semantics(button: true, selected: active, label: l10n.<formName>)`, keyboard
  focusable per the panel's existing convention.

## 9. Localization keys (designer — NEW; en/de/tr)

| Key | English | Notes |
|-----|---------|-------|
| `propertiesShape` | Shape | section label |
| `shapeFormLine` | Line | accessible thumbnail name |
| `shapeFormRectangle` | Rectangle | |
| `shapeFormEllipse` | Ellipse | |
| `shapeFormTriangle` | Triangle | |
| `shapeFormDiamond` | Diamond | |
| `shapeFormPentagon` | Pentagon | |
| `shapeFormHexagon` | Hexagon | |
| `shapeFormStar` | Star | |

Each with an `@`-description; German and Turkish translations added; localizations regenerated.

## 10. Public API delta (for `public_api_test.dart`)

- `ShapeKind`: +6 values (ellipse, triangle, diamond, pentagon, hexagon, star).
- `ShapeElement`: +`unknownForm` field, +`copyWith`.
- `JetReportDesignerController`: +`setShapeKind(String, ShapeKind)`.
- Private (NOT exported): `shapePath`, `kEllipseSegments`, `SetShapeKindCommand`, `_ShapeGallery`,
  `_ShapeThumbnail`.
