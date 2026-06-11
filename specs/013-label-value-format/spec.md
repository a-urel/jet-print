# Feature Specification: Simplified Label Value & Format Properties

**Feature Branch**: `013-label-value-format`
**Created**: 2026-06-11
**Status**: Draft
**Input**: User description: "update label value field: text field should be enough. for binding `[fieldName]`, for text `sample text` only. also, add format field to label properties."

## Clarifications

### Session 2026-06-11

- Q: How does the value field decide `[word]` is a binding vs. a literal (so `[draft]` can stay literal)? → A: Any well-formed single `[token]` always binds; an unknown field renders a localized `#ERROR`; literal bracket text is authored with an escape character.
- Q: How should advanced bindings (functions / multiple fields, formerly `$F{}`/`upper($F{name})`) be authored and presented in the single value field? → A: Via a `{ … }` template syntax with embedded `[field]` tokens — e.g. `{upper[name]}` or `{[firstName] [lastName]}`; literal text continues to use the escape character. This is the canonical form for any non-simple binding, replacing raw `$F{}`/expression syntax in the UI.
- Q: Which starter set of Format presets should ship? → A: Seven presets — None, Integer, Decimal (2 dp), Currency, Percent, Date, Date & time.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One value field for both bound and literal labels (Priority: P1)

When a report designer selects a label (text element), the Properties panel shows a **single value input** instead of two separate inputs (a "Text" box and a "Binding" box). The designer types directly into that one field, which supports three kinds of value:

- **Simple binding** — a field name in square brackets, e.g. `[customerName]` — makes the label show that data field's value when the report runs.
- **Literal text** — anything else, e.g. `sample text` — makes the label a fixed literal. Brackets/braces can appear literally via an escape character.
- **Advanced template** — a `{ … }` wrapper containing `[field]` tokens, literal text, and/or functions, e.g. `{upper[name]}` or `{[firstName] [lastName]}` — composes or transforms field values. This is the canonical way to author functions and multi-field bindings; the old `$F{}`/raw-expression syntax is no longer exposed in the panel.

The single field always reflects what the canvas shows: a bound label reads `[customerName]` in both the field and on the canvas; a literal label reads its plain text in both places.

**Why this priority**: This is the core of the request and the smallest shippable slice. It removes the confusion of maintaining two fields (where the relationship between "Text" and "Binding" was unclear) and makes the Properties panel match the canvas's `[fieldName]` token convention. Delivering only this story already improves the editing experience meaningfully.

**Independent Test**: Select a label, type `[customerName]` into the value field, confirm the canvas shows `[customerName]` and the saved template binds that label to the `customerName` field; clear it and type `sample text`, confirm the label becomes literal text. No second field is needed for either case.

**Acceptance Scenarios**:

1. **Given** a selected label with literal text "Hello", **When** the designer views the Properties panel, **Then** a single value field shows `Hello` and there is no separate binding input.
2. **Given** a selected label, **When** the designer enters `[customerName]` in the value field and commits, **Then** the label becomes bound to the `customerName` field and the canvas renders `[customerName]`.
3. **Given** a selected label bound to `customerName`, **When** the designer opens the Properties panel, **Then** the value field shows `[customerName]` (not an internal expression form such as `$F{customerName}`).
4. **Given** a label bound to `customerName`, **When** the designer replaces the value with `Paid in full` and commits, **Then** the label becomes a literal and is no longer bound to any field.
5. **Given** the value field, **When** the designer enters `[unknownField]` referencing a field that is not in the data source, **Then** the binding is accepted, a not-found indicator is shown while editing, and the rendered output is a localized `#ERROR`.
6. **Given** the value field, **When** the designer enters an advanced template such as `{[firstName] [lastName]}` or `{upper[name]}` and commits, **Then** the label binds to that template and renders the composed/transformed result at report time.
7. **Given** a label that already carries an advanced binding authored before this change, **When** the designer selects it, **Then** the value field presents it in the `{ … }` template form (no silent loss of the binding).

---

### User Story 2 - Format property for labels (Priority: P2)

The Properties panel for a label gains a **Format** field so the designer can control how a value is displayed (e.g. thousands separators for amounts, a date layout for dates) without writing any formatting expression.

The Format field is a free-text input that accepts a formatting pattern, accompanied by a small set of quick-pick presets (e.g. Currency, Date, Percent, Integer) that fill the pattern in. Leaving it empty means the value is shown as-is.

**Why this priority**: Formatting is a distinct, additive capability layered on top of the unified value field. It is valuable but not required for the value-field simplification to ship, so it follows P1. It replaces the need to hand-write a `FORMAT(...)` formatting expression for common cases.

**Independent Test**: Select a label bound to a numeric field, set Format to a thousands-separator pattern (or pick the Integer/Currency preset), and confirm the rendered output is formatted accordingly; clear the Format field and confirm the value renders unformatted.

**Acceptance Scenarios**:

1. **Given** a selected label, **When** the designer views the Properties panel, **Then** a Format field is present with an empty default and a set of quick-pick presets.
2. **Given** a label bound to a numeric field, **When** the designer enters a thousands-separator pattern (e.g. `#,##0.00`) or picks a numeric preset, **Then** the rendered value applies that pattern (e.g. `1234.5` → `1,234.50`).
3. **Given** a label bound to a date field, **When** the designer enters a date pattern (e.g. `yyyy-MM-dd`) or picks the Date preset, **Then** the rendered value applies that date layout.
4. **Given** a label, **When** the designer picks a preset, **Then** the Format field is populated with that preset's pattern (the designer can then edit it).
5. **Given** a label with a Format set, **When** the designer clears the Format field, **Then** the value renders without any formatting applied.

---

### Edge Cases

- **Literal text that looks like a binding**: A value of exactly `[name]` (a single, well-formed token spanning the whole value) is **always** a binding — even if `name` is not a field in the current data source (in which case the rendered output is a localized `#ERROR`, see FR-007). To author literal text that visually resembles a token (e.g. literal `[draft]`), the designer uses an **escape character** so the brackets are kept verbatim. Mixed or malformed bracket content (e.g. `Total: [x] of [y]`) is treated as literal. The exact escape character is a design detail to settle in planning.
- **Empty value**: An empty value field produces an empty literal label (no binding, no error).
- **Whitespace inside brackets**: `[ customerName ]` — assumed trimmed to `customerName`; surrounding spaces do not create a new field.
- **Pre-existing complex expressions**: Templates created before this change (or imported) may carry advanced bindings beyond a single field reference (functions, arithmetic, multiple fields). Such labels still render as before. When opened in the value field, the binding is presented in the `{ … }` template form (e.g. `{upper[name]}`); the designer can edit it there or replace it with a plain `[field]`/literal. The `{ … }` template grammar and the legacy-expression mapping (with a read-only `{ raw }` display for expressions outside the grammar) are specified in [research.md](research.md) §2.
- **Format on a value that cannot be formatted**: A format pattern applied to a value type it does not fit (e.g. a number pattern on a text value) leaves the value shown as-is rather than erroring.
- **Format on a literal label**: A format pattern set on a label whose value is literal text is assumed to have no visible effect (formatting targets resolved data values).
- **Invalid format pattern**: A malformed pattern falls back to showing the unformatted value rather than crashing or blanking the label.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The label Properties panel MUST present a single value input that replaces the previously separate "Text" and "Binding" inputs.
- **FR-002**: When the value input contains a single well-formed `[fieldName]` token spanning the whole value, the label MUST be treated as bound to that data field — regardless of whether that field currently exists in the data source.
- **FR-003**: When the value input contains any other content, the label MUST be treated as a literal whose text is exactly that content. The input MUST support an escape character so a designer can author literal text that contains brackets (e.g. literal `[draft]`) without it being interpreted as a binding.
- **FR-004**: For a bound label, the value input MUST display the binding in `[fieldName]` token form, matching what the canvas shows (not an internal expression syntax such as `$F{...}`).
- **FR-005**: Editing the value input from a binding to literal text (or vice versa) MUST update the label's bound/literal state accordingly, as a single undoable edit.
- **FR-006**: The value input MUST support an advanced **template** binding written as `{ … }` containing `[field]` tokens, literal text, and function applications (e.g. `{upper[name]}`, `{[firstName] [lastName]}`). This `{ … }` form MUST be the only way to author functions or multi-field bindings in the panel; the raw `$F{}`/full-expression syntax MUST NOT be exposed to the designer.
- **FR-006a**: A label carrying a `{ … }` template binding MUST render the composed/transformed value at report time, and the value field MUST display the binding in that same `{ … }` form (consistent between field and canvas, no silent loss when re-opened).
- **FR-007**: A binding to a field that is not present in the active data source MUST be accepted (not rejected); the designer MUST see a "field not found" indicator while editing. In a **schema-aware render context** (designer canvas/preview, where the data source's fields are known), the rendered output for such an unresolved binding MUST be a localized `#ERROR` token. A headless render with no declared field set leaves existing behavior unchanged (the field resolves empty).
- **FR-008**: The label Properties panel MUST add a Format input that controls how the label's value is displayed.
- **FR-009**: The Format input MUST accept a free-text formatting pattern and MUST offer these quick-pick presets that populate the pattern: None, Integer, Decimal (2 decimal places), Currency, Percent, Date, and Date & time. Picking a preset other than None fills the field with that preset's pattern (which the designer may then edit); None clears it.
- **FR-010**: An empty Format MUST render the value unformatted (no change to current behavior for labels without a format).
- **FR-011**: A non-empty Format MUST apply the pattern to the resolved value when the report renders (e.g. numeric grouping/decimals, date layouts), consistent with the existing formatting behavior available through expressions.
- **FR-012**: A Format pattern that does not apply to the value's type, or is malformed, MUST fall back to the unformatted value without erroring or blanking the label.
- **FR-013**: The value and Format edits MUST persist with the template and round-trip through save/load without loss.
- **FR-014**: New Properties-panel labels and controls (value field label, format field label, preset names, hints) MUST be localized in the project's supported languages (English, German, Turkish) with English fallback.
- **FR-015**: Existing templates and labels (including any with advanced bindings authored before this change) MUST continue to render unchanged; this change is to the editing surface and the new format property, not to how previously bound values resolve **for fields that exist in the data source**. (A pre-existing binding to a field *absent* from the data source may now surface `#ERROR` in schema-aware preview per FR-007 instead of rendering empty.)

### Key Entities *(include if data involved)*

- **Label (text element)**: A report element that displays either a fixed literal string or the value of a bound data field. Gains an associated **format** describing how its value is displayed. Its editable identity in the Properties panel is now a single value (literal text or a `[fieldName]` binding) plus an optional format pattern.
- **Field binding**: A reference from a label to a named field in the active data source, authored as `[fieldName]` and shown the same way on canvas and in the value field.
- **Template binding**: An advanced binding authored as `{ … }` mixing `[field]` tokens, literal text, and functions, used for multi-field composition and value transforms; it is the canonical replacement for raw `$F{}`/expression authoring in the panel.
- **Format pattern**: A display directive (free-text pattern, optionally seeded from a preset) applied to a label's resolved value at render time; empty means unformatted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A designer can bind a label to a data field, or make it literal, using exactly one input field (down from two) — verified by the Properties panel showing a single value control for any selected label.
- **SC-002**: For a bound label, the value field and the canvas display the identical `[fieldName]` token in 100% of cases (no divergence between what the field shows and what the canvas shows).
- **SC-003**: A designer can apply common numeric and date formatting to a bound value without typing any formatting expression, using the Format field's free-text pattern or a preset.
- **SC-004**: Switching a label between bound and literal, or changing its format, is a single undoable action and survives a save/load round-trip with no data loss in 100% of cases.
- **SC-005**: 100% of templates authored before this change continue to render the same resolved/formatted output as before (no regression) for bindings whose referenced fields exist in the data source.
- **SC-006**: All new Properties-panel text is available in English, German, and Turkish, with English shown as a fallback when a translation is missing.

## Assumptions

- The single value field uses the same `[fieldName]` ↔ field-binding convention already used for the canvas token display, so binding and canvas stay visually consistent.
- The value field recognizes three forms: a plain `[fieldName]` simple binding, a `{ … }` advanced template (functions / multiple fields / literal mix), and otherwise literal text. The `{ … }` template is the panel-facing syntax for the capabilities formerly written as raw `$F{}`/expressions; the underlying expression engine is unchanged.
- The Format field reuses the project's existing value-formatting semantics (the same patterns the current `FORMAT` formatting function understands), now surfaced as a property instead of requiring an expression.
- Format presets are a fixed starter set of seven (None, Integer, Decimal (2 dp), Currency, Percent, Date, Date & time); the exact patterns each preset fills in are a planning detail, drawn from the existing number/date formatting patterns.
- Formatting targets resolved data values; applying a format to a purely literal label has no visible effect.
- Supported localization languages are English, German, and Turkish, matching the existing designer chrome.
- No template schema-breaking change is intended; the format property is additive and previously saved templates load without migration friction.
- This change affects only labels (text elements); other element types are out of scope.
