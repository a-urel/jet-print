# Quickstart — Band Model Reification

How the reified model is used, end to end. (Illustrative; names per the design.)

## Host: build and render a ReportDefinition (the invoice, one per page)

```dart
final invoice = ReportDefinition(
  name: 'Invoice',
  page: PageFormat.a4Portrait,
  furniture: PageFurniture(
    pageHeader: Band(id: 'ph', type: BandType.pageHeader, height: 20, elements: [/* running title */]),
    pageFooter: Band(id: 'pf', type: BandType.pageFooter, height: 20, elements: [/* "Page $V{PAGE_NUMBER} of $V{PAGE_COUNT}" */]),
  ),
  body: ReportBody(
    root: DetailScope(
      id: 'root',                       // master scope: collectionField == null
      groups: [
        GroupLevel(
          id: 'g.invoice', name: 'invoice', key: r'$F{invoiceNo}',
          startNewPage: true, keepTogether: true,
          header: Band(id: 'gh', type: BandType.groupHeader, height: 80, elements: [/* INVOICE, customer, date, column labels */]),
          footer: Band(id: 'gf', type: BandType.groupFooter, height: 32, elements: [/* Subtotal $F{total} */]),
        ),
      ],
      children: [
        NestedScope(DetailScope(
          id: 'lines', collectionField: 'lines',
          children: [ BandNode(Band(id: 'line', type: BandType.detail, height: 22, elements: [/* description/qty/unitPrice/lineTotal */])) ],
        )),
      ],
    ),
  ),
);

final report = JetReportEngine().render(invoice, invoiceDataSource(), options: RenderOptions(...));
// preview / toPdf / pageToPng / print — all consume the one RenderedReport, byte-identical to today.
```

## Host: load an existing (v1) report

```dart
final def = JetReportFormat.decodeJson(oldV1Json); // schemaVersion:1 → migrated to v2 ReportDefinition, losslessly
// def renders identically to how the v1 report rendered before the migration.
```

## Author: validate before render

```dart
final problems = validate(invoice);   // List<Diagnostic>; empty == valid
// e.g. a $F{} binding placed on furniture, or a duplicate group name, is reported here —
// the designer surfaces these at author time, not as late render diagnostics.
```

## Author: in the designer (Phase 3)

- Select a **group** (not a band) → one inspector with its key + keep-together +
  reprint + start-new-page. No duplicated control on the header/footer.
- Add / remove / reorder / retype bands; create / delete groups and detail
  scopes — each one undoable step.
- Build the full invoice above (page chrome + per-invoice header/footer + nested
  lines + one invoice per page) entirely in the UI, no hand-edited model.

## Verify

- `flutter test packages/jet_print` — model, codec/migration, engine-parity
  goldens, designer.
- The existing render golden suite passes **unchanged** (byte-identical).
