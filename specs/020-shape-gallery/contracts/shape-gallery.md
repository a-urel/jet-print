# Contract: Shape Gallery in Properties Pane

Behavioral contracts for the feature, each mapped to functional requirements and grouped into the test
suites that prove them. "The controller" is `JetReportDesignerController`; "the gallery" is the
`_ShapeGallery` section in the Properties panel.

## C1 — Gallery visibility is shape-gated

- **C1.1** When a single `ShapeElement` is selected, the Properties pane shows a shape section with
  eight selectable thumbnails. *(FR-001, FR-002)*
- **C1.2** When a text, image, or barcode element is selected, no shape gallery appears. *(FR-010)*
- **C1.3** With nothing selected, no shape gallery appears. *(FR-010)*
- **C1.4** The gallery offers exactly: line, rectangle, ellipse, triangle, diamond, pentagon, hexagon,
  star — no more, no fewer. *(FR-002)*

## C2 — Active-form highlight

- **C2.1** The thumbnail matching the selected shape's current `kind` is visibly highlighted, and is the
  only highlighted item. *(FR-003, SC-006)*
- **C2.2** A shape loaded with an unrecognized form (`unknownForm != null`, rendered as rectangle) does
  **not** highlight the rectangle thumbnail as a deliberate choice — the highlight reflects the
  preserved-unknown state per the panel's convention (no false "rectangle is your pick" signal). *(FR-009)*

## C3 — Picking a form

- **C3.1** Clicking a thumbnail other than the active one changes the selected shape's `kind` to that
  form. *(FR-004)*
- **C3.2** The change preserves the element's `bounds` (position + size) and `style` (fill, stroke,
  stroke width). *(FR-004, FR-011)*
- **C3.3** Every form is drawn within the element's existing bounds box — form changes, geometry does
  not. *(FR-011)*
- **C3.4** Clicking the already-active form is a no-op: no model change, no history entry, no
  notification. *(FR-005)*

## C4 — Undo / redo

- **C4.1** A form change is a single undoable step; one Undo restores the previous form. *(FR-006, SC-005)*
- **C4.2** One Redo reapplies the new form. *(FR-006, SC-005)*
- **C4.3** No orphaned intermediate history steps are produced by a single pick. *(SC-005)*

## C5 — Line / flip coherence (edge cases)

- **C5.1** Switching from a filled rectangle to a line does not error; the line renders (stroke only,
  no fill). *(spec edge case)*
- **C5.2** Switching from a line to any closed form resets the line-only `flipDiagonal` to false, so the
  option stays coherent for non-line forms. *(spec edge case)*
- **C5.3** Switching back to a line yields a fillable-coherent line (default diagonal). *(spec edge case)*
- **C5.4** A 1×1 or extremely thin bounds renders each form without error (degenerate path is safe).
  *(spec edge case)*

## C6 — Geometry (`shapePath`)

- **C6.1** For each closed form, `shapePath(kind, bounds)` returns a path that starts with `MoveTo`,
  contains the form's expected vertex count via `LineTo`, and ends with `ClosePath`. *(FR-008)*
- **C6.2** Every produced vertex lies within (or on) the bounds rectangle. *(FR-011)*
- **C6.3** Regular polygons (pentagon, hexagon) are point-up and equilateral when bounds are square;
  the star alternates outer/inner radius at the configured ratio. *(spec Assumptions)*
- **C6.4** A degenerate (1×1 / 1×N) box does not throw. *(spec edge case)*

## C7 — Rendering fidelity (WYSIWYG)

- **C7.1** Each new form emits exactly one `PathPrimitive` whose `commands` equal `shapePath(kind, bounds)`;
  rectangle/line keep emitting `RectPrimitive`/`LinePrimitive`. *(FR-008)*
- **C7.2** A page containing each new form renders **identically** on the design canvas, in preview, and
  in PDF/PNG export (one shared render path; golden-verified). *(FR-008, SC-003)*
- **C7.3** Existing line/rectangle goldens remain byte-identical (no regression). *(FR-008)*
- **C7.4** The gallery thumbnail for a form draws the same geometry as the rendered shape (shared
  `shapePath`), so the picker cannot diverge from the result. *(FR-008, SC-006)*

## C8 — Persistence & backward compatibility

- **C8.1** A chosen form survives save→reload unchanged for every form. *(FR-007, SC-004)*
- **C8.2** A report authored before this feature (only line/rectangle) loads byte-for-byte unchanged;
  `kReportSchemaVersion` stays 1. *(FR-007, FR-009, SC-004)*
- **C8.3** A serialized form this version does not recognize loads without error, renders as a rectangle,
  and re-serializes the **original** form name (lossless round-trip). *(FR-009, SC-004)*
- **C8.4** After a deliberate gallery pick on an unknown-form shape, `unknownForm` is cleared and the
  chosen form serializes. *(FR-009)*

## C9 — Accessibility & localization

- **C9.1** Each gallery item exposes a button role and a localized accessible name (its form name).
  *(FR-012)*
- **C9.2** Items are reachable and activatable via keyboard. *(FR-012)*
- **C9.3** The section label and all eight form names render correctly in English, German, and Turkish.
  *(FR-012)*

---

## Test groups (Test-First — write red, then implement)

| Group | File(s) | Covers |
|-------|---------|--------|
| **Geometry** | `test/rendering/elements/shape_path_test.dart` | C6.1–C6.4 |
| **Renderer** | `test/rendering/elements/shape_element_renderer_test.dart` (extend) | C7.1; rectangle/line unchanged |
| **Domain** | `test/domain/elements/shape_element_test.dart` | `copyWith`, equality incl. `unknownForm` |
| **Codec** | `test/domain/serialization/shape_element_codec_test.dart` | C8.1–C8.4 round-trip truth table |
| **Command** | `test/designer/controller/set_shape_kind_command_test.dart` | C3.4, C4.1–C4.3, C5.2, C8.4; single-undo, notify-once |
| **Properties widget** | `test/designer/properties_editor_test.dart` (extend) | C1.1–C1.4, C2.1–C2.2, C3.1–C3.3, C5.1/C5.3 via UI |
| **Accessibility** | `test/designer/accessibility_semantics_test.dart` (extend) | C9.1–C9.2 |
| **Localization** | `test/designer/localization_test.dart` (extend) | C9.3 |
| **Goldens** | `test/designer/goldens/shape_forms_*.png` | C7.2–C7.3 (canvas/preview/export agree; no regression) |
| **Public API** | `test/public_api_test.dart` (update) | records enum + `setShapeKind` + `copyWith`/`unknownForm` |

A change does not merge with any failing or skipped test (Constitution III).
