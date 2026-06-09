# Quickstart: Data-Aware Designer (Invoice MVP)

**Feature**: 009-data-aware-designer | **Date**: 2026-06-09

This shows how a **consumer** (e.g. the playground) makes the designer data-aware with an invoice master/detail structure — using only the public API (`package:jet_print/jet_print.dart`). It mirrors what the playground's `invoice_sample.dart` will ship.

> Scope reminder: this iteration is **tokens only**. You describe structure, attach it, and bind elements; the designer shows **field tokens** at design time. Filling/rendering real values is the deferred render slice.

---

## 1. Describe the invoice structure (`JetDataSchema`)

A master invoice record with a nested `lines` collection (arbitrary depth is allowed — `lines` could itself contain a collection).

```dart
import 'package:jet_print/jet_print.dart';

final JetDataSchema invoiceSchema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    const FieldDef('invoiceNo', type: JetFieldType.string),
    const FieldDef('customerName', type: JetFieldType.string),
    const FieldDef('date', type: JetFieldType.dateTime),
    const FieldDef('total', type: JetFieldType.double),
    // The master/detail relationship: a field whose type IS a collection,
    // carrying its own child schema.
    const FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
      FieldDef('qty', type: JetFieldType.integer),
      FieldDef('unitPrice', type: JetFieldType.double),
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ],
);
```

## 2. Attach it to the designer

```dart
JetReportDesigner(
  controller: _controller,
  dataSchema: invoiceSchema,          // NEW — the Data Source panel now shows this tree
  onSaveRequested: _save,
  onOpenRequested: _open,
);
```

The Data Source panel now shows **Invoice → {invoiceNo, customerName, date, total, lines ▸}**, and expanding **lines** reveals **{description, qty, unitPrice, lineTotal}**. With no `dataSchema`, the panel shows an empty state (no placeholder).

## 3. Bind elements (two ways)

- **Drag** a leaf field (e.g. `customerName`) from the panel onto a header band → a bound text element appears showing a token like `«customerName»`.
- **Properties panel**: select an element, pick a field or type an expression (`$F{total}`, or richer like `upper($F{customerName})`), or press **Clear** to revert to static text.

Bindings live in the model you already know: a bound `TextElement` carries `expression`; a bound `ImageElement` carries `FieldImageSource('logo')`.

## 4. Author the master/detail layout

- Place header fields (`invoiceNo`, `customerName`, `date`) in a **master** band (no collection binding) — they resolve against the invoice record.
- Designate the **detail** band as bound to the `lines` collection (drag `lines` onto a band, or set it in Properties). It now represents the **repeating lines**; elements inside bind to `description`, `qty`, `unitPrice`, `lineTotal` (child scope).
- For deeper nesting, place a collection-bound band **inside** the lines band bound to a child collection.

## 5. Save / open (lossless, self-describing)

```dart
final String json = JetReportFormat.encodeJson(controller.template); // bindings + master/detail persist
final ReportTemplate reopened = JetReportFormat.decodeJson(json);
```

Reopening **without** re-attaching `dataSchema` still shows every bound token (bindings are self-describing); the panel tree is empty until you attach a schema again, after which any binding referencing a missing/out-of-scope field is flagged **unresolved** (never dropped).

---

## Verify (developer loop, from repo root)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/jet_print apps/jet_print_playground
# Goldens (after intentional visual changes):
flutter test --update-goldens packages/jet_print
```

Run the sample:

```bash
flutter run -d macos --target apps/jet_print_playground/lib/main.dart
```

You should see the invoice structure in the Data Source panel and (if the bundled sample template is loaded) a master/detail invoice layout with bound tokens.
