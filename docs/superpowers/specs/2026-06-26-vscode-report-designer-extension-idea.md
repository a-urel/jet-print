# VS Code Report Designer Extension — Idea / Future Work

> **Status: PARKED (not scheduled).** Captured from a brainstorming session on 2026-06-26.
> This is a deferred idea doc, *not* an approved design ready for a plan. Re-open the
> brainstorm before implementing.

## Intent

Let a developer building a Flutter app that consumes `jet_print` author report templates
**visually**, save them as `.jetreport` files in their repo, and ship those files as
**app assets** loaded at runtime. ("Reports embedded into the program during development.")

Primary use case **(A)**: authoring downstream-app report assets.
Secondary / nice-to-have **(B)**: dogfooding — designing jet-print's own sample/playground
reports from inside the editor.

## Decisions captured this session

| # | Question | Decision |
|---|----------|----------|
| Q1 | What "embed into program" means | **A** (+ optionally B): visual designer authors `.jetreport` files that ship as downstream-app assets. |
| Q2 | Preview/schema data | Sidecar files: `report.jetreport` (definition) + `report.jetreport.schema` (field schema + **optional** sample data). Schema file is **design-time only**; the runtime app supplies a real datasource for design/print/etc. |
| Q3 | Distribution / who runs it | **A** — standalone Marketplace extension. Bundles a **prebuilt Flutter-web designer** (pinned `jet_print` version). End user needs **no Flutter SDK**. Report-format version pinned per extension release. |
| Q4 | MVP scope | **A,B,C,D,E** (not F). A: visual open/edit/save of `.jetreport`. B: load sidecar schema → resolve fields + preview with its sample data. C: live Preview (rendered report). D: `Jet: New Report` scaffold command. E: Export PDF/PNG. **F (visual schema/sample-data editor) → backlog.** |

## Enablers already shipped (low remaining lift on the engine side)

- `JetReportFormat.encodeDefinitionJson` / `decodeDefinitionJson` — public, versioned,
  lossless JSON **text** format → reports are Git-friendly text files.
- `JetReportDesigner` / `JetReportWorkspace` — public designer widgets, with host
  **Open/Save** callbacks (shown only when wired) and an **`onError`** sink — exactly the
  seam a webview host needs to bridge file I/O. (See host-callback-hardening work.)
- **Flutter web support DONE** (CanvasKit, `XFile` open/save); playground already
  web-buildable. The designer runs in a browser today.

## Two artifacts any implementation needs (in this repo)

1. **Flutter-web designer-host app** (new, e.g. `apps/jet_print_designer_host`)
   - Mounts `JetReportWorkspace`; wires host callbacks to a JS `postMessage` bridge.
   - Inbound (host←extension): `init` (doc text, schema, sample data, theme, locale),
     `load`, `requestSave`, `setTheme`, `applySchema`.
   - Outbound (host→extension): `ready`, `change` (serialized text + dirty), `save`,
     `error` (from `onError`), `requestSchema`, `export` (PDF/PNG bytes), `print`.
   - Round-trips text via `JetReportFormat`. Builds schema/sample into a design-time
     data source for preview.
2. **VS Code extension** (new, TypeScript, e.g. `tools/vscode-jet-print`)
   - `CustomTextEditorProvider` for `*.jetreport`; webview loads the bundled Flutter-web build.
   - Reads sidecar `<name>.jetreport.schema` via `workspace.fs`; bridges document text;
     theme sync; `Jet: New Report` scaffold; export → write file; external-edit refresh
     with an echo/revision guard.

## Architecture options (chosen vs alternatives)

1. **Custom Text Editor + bundled Flutter-web host** ⭐ *recommended end-state*
   - `.jetreport` stays a text document → free dirty/save/undo-in-file + **Git text diffs**.
     Designer is source of truth; posts serialized text back per edit; extension applies a
     `WorkspaceEdit`. Zero SDK, idiomatic, matches Q3=A.
   - Risks: Flutter-web-in-webview plumbing (CSP/wasm, base href, no service worker,
     `asWebviewUri` asset rewriting, theme); designer-undo vs text-undo is coarse; echo-loop
     guard on external file edits; CanvasKit bundle size (a few MB).
2. **Custom (binary) Editor owning the document** — cleaner designer-driven undo/save, but
   loses native text diff/merge and adds plumbing.
3. **Local server / launch process** — webview points at a localhost Flutter server; dodges
   CSP/asset rewriting but needs port mgmt + a running process; doesn't bundle clean for
   Marketplace. Keep as a **dev fallback / CSP escape hatch**.

## Recommendation: stage by evidence (do NOT start with #1)

The *workflow* (visual authoring → repo asset) is worth it. Embedding Flutter-web in a
VS Code webview is the **most expensive, highest-maintenance** way to reach it (re-breaks on
Flutter SDK bumps; adds a TS extension + Flutter host + second CI + Marketplace release +
pinned-format support matrix to a Dart monorepo), for a package whose user base is small
today. Validate demand cheaply first:

1. **Standalone web/desktop designer app** — small lift over the existing web-buildable
   playground. Dev opens `.jetreport`, edits, saves to repo. Same asset workflow, no webview
   hell. Deploy the web build to a URL = zero install. **Delivers ~80% of the value now.**
2. **Thin VS Code extension** — *no* embedded designer. Commands only: `Jet: New Report`
   (scaffold `.jetreport` + starter `.schema`), `Open in Jet Designer` (launch #1 with the
   file), `Export`; file association + right-click. Tiny TS, no Flutter-in-webview.
3. **Full embedded-webview editor** (architecture option 1 above) — build **only if devs
   actually pull for in-editor WYSIWYG**. Same end-state, reached by evidence.

## Open questions for the future re-brainstorm

- Document-sync model: confirm Custom Text Editor vs binary; undo-stack reconciliation.
- CSP / wasm viability spike for CanvasKit inside a VS Code webview (the make-or-break risk).
- `.jetreport.schema` file format (reuse an existing schema/data-source codec? new schema doc?).
- Format-version skew: bundled-pinned designer vs the report file's format version.
- Marketplace release pipeline + how the Flutter-web build is produced/bundled in CI.
