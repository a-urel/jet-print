# Quickstart: Unified Context-Switching Toolbar

How a host uses the unified toolbar. The headline: **existing hosts get the mode switch for free**,
and rename costs at most one extra callback in preview.

---

## Designer mode — zero new wiring

`JetReportDesigner` already takes `onPreviewRequested`. That callback now also backs the **Preview**
segment of the mode switch, and inline rename is fully internal (it calls `controller.rename` through
the ambient `DesignerScope`). No host change is required for the switch or for renaming in designer.

```dart
final controller = JetReportDesignerController();

JetReportDesigner(
  controller: controller,
  onSaveRequested: (ReportTemplate t) => writeFile(JetReportFormat.encodeJson(t)),
  onOpenRequested: () async => controller.open(JetReportFormat.decodeJson(await readFile())),
  // Backs both the "Preview" toolbar action AND the new Preview segment of the mode switch:
  onPreviewRequested: (ReportTemplate t) => _openPreview(t),
);
```

Renaming in designer: the user clicks the edit affordance next to the name, types, presses Enter (or
clicks away). Internally the toolbar calls `controller.rename(value)` — a single undoable step. The
new name is on `controller.template.name`, so your existing Save flow persists it unchanged.

---

## Preview mode — one optional callback for rename

`JetReportPreview` already takes `onBack` (it now also backs the **Designer** segment of the switch)
and `onExportPdf` / `onPrint`. To allow renaming from preview, wire the new `onRename` to the same
controller:

```dart
final RenderedReport report = const JetReportEngine().render(controller.template, source);

JetReportPreview(
  report: report,
  onBack: () => Navigator.of(context).pop(),     // also = "switch to Designer"
  onExportPdf: () => JetReportExporter.toPdf(report),
  onPrint: () => JetReportPrinter.printReport(report),
  // NEW — renaming from preview updates the same template name field:
  onRename: (String name) => controller.rename(name),
);
```

The preview toolbar shows the typed name immediately and calls `onRename`; because you routed it to
`controller.rename`, the next preview/export/save carries the new name. If you omit `onRename`, the
edit affordance is hidden in preview (designer-only rename).

> The switch reflects the mode it is given: the designer shell shows **Designer** active, the preview
> shell shows **Preview** active. Your app owns the actual swap (here, a `Navigator` push/pop) — the
> toolbar only emits the request via `onPreviewRequested` / `onBack`.

---

## The end-to-end round-trip (what the playground demonstrates)

1. Open a report in the designer — the unified toolbar shows the name (or "Untitled report"), the
   **Designer|Preview** switch with Designer active, and the editing actions on the right.
2. Rename it inline (Enter to commit). The new name shows immediately; `controller.template.name`
   updates; undo restores the old name.
3. Click the **Preview** segment → the host swaps to `JetReportPreview`. The same toolbar shell now
   shows Preview active and viewing actions (export/print/zoom/page-nav) on the right; the title
   shows the new name.
4. Click the **Designer** segment (or back) → the host returns; all edits, undo/redo history, and
   selection are intact.

---

## Localization

Wire the library's delegate and locales (unchanged from before); the new switch/rename strings ship
in en/de/tr:

```dart
ShadApp(
  localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
  supportedLocales: JetPrintLocalizations.supportedLocales,
  home: ...,
);
```

New keys: `modeDesigner`, `modePreview`, `actionRenameTooltip`, `renameFieldLabel`.
