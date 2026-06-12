# JetReportWorkspace Keep-Alive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `JetReportWorkspace` widget that keeps the designer and preview both mounted (instant mode switching) and renders the preview behind a loading indicator (visible feedback for the first large-data render).

**Architecture:** One new public `StatefulWidget` in the library composes the existing `JetReportDesigner` and `JetReportPreview` inside an `IndexedStack` (both children stay alive, so switching is a visibility toggle — no rebuild, no canvas re-record). It owns the workspace mode and the rendered report: entering preview defers `render()` one frame and shows an indeterminate `ShadProgress` until the report is ready, caching by template identity so an unedited round trip is free. No change to the render engine, serialization, or the existing designer/preview widgets.

**Tech Stack:** Dart/Flutter, `shadcn_ui ^0.54.0` (`ShadProgress`, `ShadSeparator`, `ShadTheme`, `LucideIcons`), the private 017 shell widgets (`UnifiedTopBar`, `WorkspaceModeSwitch`, `WorkspaceMode`).

---

## Background the engineer needs

- **Reference design:** [docs/superpowers/specs/2026-06-12-workspace-keep-alive-design.md](../specs/2026-06-12-workspace-keep-alive-design.md).
- **Why keep-alive fixes "back to design":** the designer canvas is a cached `ui.Picture`; unmounting on switch forces an async re-record (blank gap). `IndexedStack` keeps the `State` alive so the cached picture re-blits in one frame.
- **`render()` is synchronous and data-proportional** (`packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart`). It returns a lazily-paginated `RenderedReport`. The workspace does not change it — it only defers *when* it is called and shows feedback meanwhile.
- **`ShadProgress(value: null)` is an indeterminate (looping) linear bar.** Its `flutter_animate` ticker never settles, so **any widget test that has the loading bar on-screen must use `tester.pump(Duration)` — never `pumpAndSettle()`** (which would hang). Once the report is ready the bar is unmounted, so `pumpAndSettle()` is fine again for the preview's async page record.
- **Mode-switch segment keys (already stable):** `ValueKey('jet_print.toolbar.mode.designer')` and `ValueKey('jet_print.toolbar.mode.preview')`. In the designer top bar the **Preview** segment fires `onPreviewRequested`; in the preview/loading bar the **Designer** segment fires the back/switch request.
- **`IndexedStack` puts non-selected children offstage.** `find.byKey(...)` skips offstage by default; pass `skipOffstage: false` to assert a child is still *mounted* while it is the inactive mode.
- **Run tests from the repo root:** `flutter test packages/jet_print` and `flutter test apps/jet_print_playground`. Always `cd` back to the repo root after a `flutter` command (it leaves cwd inside the package).

## File structure

| File | Responsibility |
|------|----------------|
| `packages/jet_print/lib/src/designer/jet_report_workspace.dart` | **NEW.** The `JetReportWorkspace` widget + its `_JetReportWorkspaceState`, the `ReportRenderCallback` typedef, and the private `_LoadingScaffold`/`_LoadingBar`. |
| `packages/jet_print/lib/jet_print.dart` | **MODIFY.** Export `JetReportWorkspace` (and `ReportRenderCallback`). |
| `packages/jet_print/test/public_api_test.dart` | **MODIFY.** Assert `JetReportWorkspace` is constructible from the public surface. |
| `packages/jet_print/test/designer/jet_report_workspace_test.dart` | **NEW.** Keep-alive, mode switch, deferred render + loading, identity caching, sequence guard, export/print wiring. |
| `apps/jet_print_playground/lib/main.dart` | **MODIFY.** Replace the `Navigator.push` preview path with `JetReportWorkspace`. |
| `apps/jet_print_playground/test/app_consumes_library_test.dart` | **MODIFY.** Assert the app renders a `JetReportWorkspace` wrapping the designer. |
| `packages/jet_print/CHANGELOG.md` | **MODIFY.** Note the new workspace widget. |

---

## Task 1: Scaffold `JetReportWorkspace` (designer pass-through) + export

Smallest vertical slice: the widget exists, is reachable from the public API, and renders the designer. No mode switching yet.

**Files:**
- Create: `packages/jet_print/lib/src/designer/jet_report_workspace.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Modify: `packages/jet_print/test/public_api_test.dart`

- [ ] **Step 1: Write the failing public-API test**

Add to the end of `main()` in `packages/jet_print/test/public_api_test.dart`:

```dart
  test('JetReportWorkspace is constructible from the public surface', () {
    final JetReportDesignerController controller = JetReportDesignerController();
    addTearDown(controller.dispose);
    final JetReportWorkspace workspace = JetReportWorkspace(
      controller: controller,
      renderReport: (ReportTemplate t) => const JetReportEngine().render(
        t,
        JetInMemoryDataSource(const <Map<String, Object?>>[]),
      ),
    );
    expect(workspace, isA<Widget>());
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test packages/jet_print/test/public_api_test.dart`
Expected: FAIL — `JetReportWorkspace` is not defined.

- [ ] **Step 3: Create the widget (designer pass-through only)**

Create `packages/jet_print/lib/src/designer/jet_report_workspace.dart`:

```dart
/// A keep-alive designer↔preview workspace (see
/// docs/superpowers/specs/2026-06-12-workspace-keep-alive-design.md).
///
/// Composes [JetReportDesigner] and [JetReportPreview] in an [IndexedStack] so
/// both stay mounted: switching modes is a pure visibility toggle (instant in
/// both directions, no canvas re-record). Entering preview renders the report
/// behind a loading indicator, caching it by template identity so an unedited
/// round trip is free.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/data_schema.dart';
import '../domain/report_template.dart';
import '../rendering/engine/rendered_report.dart';
import 'controller/jet_report_designer_controller.dart';
import 'jet_report_designer.dart';
import 'layout/unified_top_bar.dart';
import 'layout/workspace_mode_switch.dart';
import 'preview/jet_report_preview.dart';

/// Renders [template] into a [RenderedReport] for the preview. The host owns the
/// data source and render options; returning a `Future` lets a host render
/// off-thread without an API change (the workspace shows its loading indicator
/// until it completes).
typedef ReportRenderCallback = FutureOr<RenderedReport> Function(
    ReportTemplate template);

/// One workspace that hosts both the report designer and its preview, keeping
/// both alive so switching between them is instant.
///
/// ```dart
/// JetReportWorkspace(
///   controller: controller,
///   dataSchema: schema,
///   renderReport: (ReportTemplate t) =>
///       JetReportEngine().render(t, dataSource, options: options),
///   onSaveRequested: (ReportTemplate t) => write(JetReportFormat.encodeJson(t)),
///   onExportPdf: (RenderedReport r) => save(JetReportExporter().toPdf(r)),
/// );
/// ```
class JetReportWorkspace extends StatefulWidget {
  /// Creates the workspace over [controller], rendering the preview with
  /// [renderReport].
  const JetReportWorkspace({
    super.key,
    required this.controller,
    required this.renderReport,
    this.dataSchema,
    this.onSaveRequested,
    this.onOpenRequested,
    this.onExportPdf,
    this.onPrint,
    this.loadingBuilder,
  });

  /// The model + undo history shared with the designer canvas and panels.
  final JetReportDesignerController controller;

  /// Produces the [RenderedReport] shown in preview from the live template.
  final ReportRenderCallback renderReport;

  /// The data-source structure shown in the designer's Data Source panel.
  final JetDataSchema? dataSchema;

  /// Forwarded to the designer's Save action (the host persists the template).
  final ReportSaveRequestedCallback? onSaveRequested;

  /// Forwarded to the designer's Open action.
  final ReportOpenRequestedCallback? onOpenRequested;

  /// Invoked with the **current** rendered report when the preview's export
  /// action fires; null ⇒ no export action. The host performs the I/O.
  final ValueChanged<RenderedReport>? onExportPdf;

  /// Invoked with the **current** rendered report when the preview's print
  /// action fires; null ⇒ no print action.
  final ValueChanged<RenderedReport>? onPrint;

  /// Builds the indicator shown while a render is in flight; null ⇒ a themed
  /// indeterminate [ShadProgress] bar.
  final WidgetBuilder? loadingBuilder;

  @override
  State<JetReportWorkspace> createState() => _JetReportWorkspaceState();
}

class _JetReportWorkspaceState extends State<JetReportWorkspace> {
  @override
  Widget build(BuildContext context) {
    return JetReportDesigner(
      controller: widget.controller,
      dataSchema: widget.dataSchema,
      onSaveRequested: widget.onSaveRequested,
      onOpenRequested: widget.onOpenRequested,
    );
  }
}
```

- [ ] **Step 4: Export it from the public entry point**

In `packages/jet_print/lib/jet_print.dart`, beside the existing designer export
(`export 'src/designer/jet_report_designer.dart' show JetReportDesigner;`), add:

```dart
export 'src/designer/jet_report_workspace.dart'
    show JetReportWorkspace, ReportRenderCallback;
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test packages/jet_print/test/public_api_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/jet_report_workspace.dart \
        packages/jet_print/lib/jet_print.dart \
        packages/jet_print/test/public_api_test.dart
git commit -m "feat(workspace): scaffold JetReportWorkspace (designer pass-through)"
```

---

## Task 2: Keep-alive switching, deferred render, and loading feedback

Implement the full state machine: `IndexedStack` keep-alive, mode switching wired to the existing switch events, deferred render with an indeterminate `ShadProgress`, identity-based caching, and a stale-render sequence guard.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_workspace.dart`
- Test: `packages/jet_print/test/designer/jet_report_workspace_test.dart` (new)

- [ ] **Step 1: Write the failing widget tests**

Create `packages/jet_print/test/designer/jet_report_workspace_test.dart`:

```dart
// JetReportWorkspace widget tests: keep-alive switching + deferred render with
// loading feedback. Black-box through the public API only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _modeDesignerKey = ValueKey<String>('jet_print.toolbar.mode.designer');
const Key _modePreviewKey = ValueKey<String>('jet_print.toolbar.mode.preview');
const Key _loadingKey = ValueKey<String>('jet_print.workspace.loading');
const Key _surfaceKey = ValueKey<String>('jet_print.designer.surface');
const Key _pageKey = ValueKey<String>('jet_print.preview.page');

ReportTemplate _template() => const ReportTemplate(
      name: 'Quarterly Report',
      page: _page,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
          ],
        ),
      ],
    );

RenderedReport _render(ReportTemplate t) => const JetReportEngine().render(
      t,
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Future<JetReportWorkspace> _pumpWorkspace(
  WidgetTester tester, {
  required JetReportDesignerController controller,
  ReportRenderCallback? renderReport,
  int Function()? renderCounter,
  ValueChanged<RenderedReport>? onExportPdf,
  ValueChanged<RenderedReport>? onPrint,
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final JetReportWorkspace workspace = JetReportWorkspace(
    controller: controller,
    renderReport: renderReport ?? _render,
    onExportPdf: onExportPdf,
    onPrint: onPrint,
  );
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: workspace,
  ));
  await tester.pump();
  return workspace;
}

/// Switches into preview from the designer and drives the deferred render to
/// completion. The loading bar (an indeterminate ShadProgress) forbids
/// pumpAndSettle until it is gone, so we pump explicit frames.
Future<void> _enterPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(_modePreviewKey));
  await tester.pump(); // mode → preview; loading shown; render scheduled
  await tester.pump(const Duration(milliseconds: 1)); // fire the zero-delay timer
  await tester.pumpAndSettle(); // report ready → preview records its page
}

void main() {
  testWidgets('starts in designer mode', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);

    expect(find.byKey(_surfaceKey), findsOneWidget);
    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.byKey(_pageKey), findsNothing);
  });

  testWidgets('entering preview shows the loading bar, then the rendered page',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);

    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pump(); // loading frame (render deferred by one frame)
    expect(find.byKey(_loadingKey), findsOneWidget,
        reason: 'the loading bar is visible while the first render runs');
    expect(find.byKey(_pageKey), findsNothing);

    await tester.pump(const Duration(milliseconds: 1)); // run the render
    await tester.pumpAndSettle(); // preview records its page
    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('switching back to design is instant and keeps the canvas alive',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);
    await _enterPreview(tester);

    // While in preview the designer surface is still mounted (offstage), proving
    // it was never torn down.
    expect(find.byKey(_surfaceKey, skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump(); // single frame — no re-record, no async gap
    expect(find.byKey(_surfaceKey), findsOneWidget);
    expect(find.byKey(_loadingKey), findsNothing);
  });

  testWidgets('an unedited round trip into preview reuses the report',
      (WidgetTester tester) async {
    int renders = 0;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) {
        renders++;
        return _render(t);
      },
    );

    await _enterPreview(tester);
    expect(renders, 1);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pumpAndSettle(); // no render scheduled → safe to settle
    expect(renders, 1, reason: 'unchanged template ⇒ cached report reused');
    expect(find.byKey(_pageKey), findsOneWidget);
  });

  testWidgets('editing the template re-renders on the next preview entry',
      (WidgetTester tester) async {
    int renders = 0;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) {
        renders++;
        return _render(t);
      },
    );

    await _enterPreview(tester);
    expect(renders, 1);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    // Edit: rename produces a NEW immutable template (identity changes).
    controller.rename('Edited');
    await tester.pump();
    await _enterPreview(tester);
    expect(renders, 2, reason: 'changed template ⇒ a fresh render');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test packages/jet_print/test/designer/jet_report_workspace_test.dart`
Expected: FAIL — there is no mode switch / loading bar / preview yet (the widget only renders the designer).

- [ ] **Step 3: Implement the state machine**

Replace the body of `_JetReportWorkspaceState` in
`packages/jet_print/lib/src/designer/jet_report_workspace.dart` with:

```dart
class _JetReportWorkspaceState extends State<JetReportWorkspace> {
  /// The active mode; the workspace always opens in the designer.
  WorkspaceMode _mode = WorkspaceMode.designer;

  /// The most recent rendered report, or null before the first preview render
  /// completes. Kept across switches so re-entering preview is instant.
  RenderedReport? _report;

  /// The template identity [_report] was rendered from; an unchanged identity on
  /// the next preview entry means the cached report is still valid.
  ReportTemplate? _lastRendered;

  /// Whether a render is currently in flight (drives the loading indicator).
  bool _rendering = false;

  /// Monotonic render tag so a superseded async render cannot overwrite a newer
  /// result (mirrors the preview's own record-sequence guard).
  int _renderSeq = 0;

  void _enterPreview(ReportTemplate template) {
    setState(() => _mode = WorkspaceMode.preview);
    if (_report != null && identical(template, _lastRendered)) return;
    _startRender(template);
  }

  void _enterDesigner() => setState(() => _mode = WorkspaceMode.designer);

  Future<void> _startRender(ReportTemplate template) async {
    final int seq = ++_renderSeq;
    setState(() => _rendering = true);
    // Yield one frame so the loading indicator paints before a synchronous
    // render() blocks the UI thread (a zero-delay timer, not a microtask, so it
    // runs after the current frame is drawn).
    await Future<void>.delayed(Duration.zero);
    final RenderedReport report =
        await Future<RenderedReport>.sync(() => widget.renderReport(template));
    if (!mounted || seq != _renderSeq) return;
    setState(() {
      _report = report;
      _lastRendered = template;
      _rendering = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _mode == WorkspaceMode.designer ? 0 : 1,
      sizing: StackFit.expand,
      children: <Widget>[
        JetReportDesigner(
          controller: widget.controller,
          dataSchema: widget.dataSchema,
          onSaveRequested: widget.onSaveRequested,
          onOpenRequested: widget.onOpenRequested,
          onPreviewRequested: _enterPreview,
        ),
        _buildPreviewSlot(context),
      ],
    );
  }

  Widget _buildPreviewSlot(BuildContext context) {
    final bool active = _mode == WorkspaceMode.preview;
    final RenderedReport? report = _report;
    if (report == null) {
      // Before the first render completes. The animated indicator is built only
      // while preview is the active mode, so the offstage placeholder before any
      // preview never runs a perpetual ticker.
      return _LoadingScaffold(
        name: widget.controller.template.name,
        onSwitchToDesigner: _enterDesigner,
        showIndicator: active && _rendering,
        loadingBuilder: widget.loadingBuilder,
      );
    }
    final Widget preview = JetReportPreview(
      report: report,
      onBack: _enterDesigner,
      onExportPdf:
          widget.onExportPdf == null ? null : () => widget.onExportPdf!(report),
      onPrint: widget.onPrint == null ? null : () => widget.onPrint!(report),
    );
    if (!(active && _rendering)) return preview;
    // A re-render is in flight while the previous report is still visible: keep
    // the pages and overlay the indicator just under the toolbar (no blank flash).
    return Stack(
      children: <Widget>[
        preview,
        Positioned(
          left: 0,
          right: 0,
          top: UnifiedTopBar.height,
          child: widget.loadingBuilder?.call(context) ?? const _LoadingBar(),
        ),
      ],
    );
  }
}

/// The preview-mode chrome shown while the first report renders: the shared
/// toolbar (so the switch-back affordance is present) over an optional loading
/// bar.
class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({
    required this.name,
    required this.onSwitchToDesigner,
    required this.showIndicator,
    this.loadingBuilder,
  });

  final String name;
  final VoidCallback onSwitchToDesigner;
  final bool showIndicator;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ColoredBox(
      color: colors.muted,
      child: Column(
        children: <Widget>[
          UnifiedTopBar(
            leadingIcon: LucideIcons.fileText,
            name: name,
            compactWidth: 880,
            scrollWidth: 880,
            center: WorkspaceModeSwitch(
              mode: WorkspaceMode.preview,
              onSwitchRequested: onSwitchToDesigner,
            ),
            actions: (BuildContext context, bool compact) => const <Widget>[],
          ),
          const ShadSeparator.horizontal(margin: EdgeInsets.zero),
          if (showIndicator) loadingBuilder?.call(context) ?? const _LoadingBar(),
        ],
      ),
    );
  }
}

/// The default loading indicator: a themed indeterminate progress bar.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) {
    return const ShadProgress(
      key: ValueKey<String>('jet_print.workspace.loading'),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test packages/jet_print/test/designer/jet_report_workspace_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/jet_report_workspace.dart \
        packages/jet_print/test/designer/jet_report_workspace_test.dart
git commit -m "feat(workspace): keep-alive switching + deferred render with loading feedback"
```

---

## Task 3: Export / print fire with the current rendered report

**Files:**
- Test: `packages/jet_print/test/designer/jet_report_workspace_test.dart` (extend)
- (No library change expected — the wiring is already in Task 2; this task pins it.)

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `jet_report_workspace_test.dart`:

```dart
  testWidgets('export and print fire with the current rendered report',
      (WidgetTester tester) async {
    RenderedReport? exported;
    RenderedReport? printed;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      onExportPdf: (RenderedReport r) => exported = r,
      onPrint: (RenderedReport r) => printed = r,
    );
    await _enterPreview(tester);

    await tester.tap(find.byKey(const ValueKey<String>('jet_print.preview.export')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('jet_print.preview.print')));
    await tester.pump();

    expect(exported, isNotNull);
    expect(printed, same(exported),
        reason: 'both actions act on the single current rendered report');
    expect(exported!.pageCount, 3);
  });
```

- [ ] **Step 2: Run the test**

Run: `flutter test packages/jet_print/test/designer/jet_report_workspace_test.dart -n "export and print"`
Expected: PASS (the wiring from Task 2 already passes the current report). If it FAILS, fix the `onExportPdf`/`onPrint` closures in `_buildPreviewSlot` to call the callbacks with `report`, then re-run.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/designer/jet_report_workspace_test.dart
git commit -m "test(workspace): export/print act on the current rendered report"
```

---

## Task 4: Refactor the playground to use `JetReportWorkspace`

Replace the `Navigator.push` preview route with the workspace, making the playground the reference demo.

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`
- Modify: `apps/jet_print_playground/test/app_consumes_library_test.dart`

- [ ] **Step 1: Update the consumption test (failing)**

In `apps/jet_print_playground/test/app_consumes_library_test.dart`, change the
first test to expect the workspace wrapping the designer:

```dart
  testWidgets(
    'root widget renders a JetReportWorkspace wrapping the designer',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      expect(find.byType(ShadApp), findsOneWidget);
      expect(find.byType(JetReportWorkspace), findsOneWidget);
      // The workspace opens in designer mode, so its designer is on-screen.
      expect(find.byType(JetReportDesigner), findsOneWidget);
    },
  );
```

In the second test (`the app owns a controller and wires the Save/Open
callbacks`), read the workspace instead of the designer:

```dart
      final JetReportWorkspace workspace =
          tester.widget<JetReportWorkspace>(find.byType(JetReportWorkspace));
      expect(workspace.controller, isNotNull,
          reason: 'the app owns the controller');
      expect(workspace.onSaveRequested, isNotNull,
          reason: 'Save is wired to a host persistence callback');
      expect(workspace.onOpenRequested, isNotNull,
          reason: 'Open is wired to a host persistence callback');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test apps/jet_print_playground/test/app_consumes_library_test.dart`
Expected: FAIL — the app still renders a bare `JetReportDesigner`, no `JetReportWorkspace`.

- [ ] **Step 3: Rewrite the playground host**

In `apps/jet_print_playground/lib/main.dart`:

(a) Change `_savePdf` (currently in `rendered_invoice_example.dart`) is not used
here; instead give `_PlaygroundHomeState` its own export that takes a report.
Replace the `_openPreview` method and the `_RenderedInvoicePreviewPage` class,
and the `build` body's `Stack` child, as follows.

Remove the `_openPreview` method and the entire `_RenderedInvoicePreviewPage`
class at the bottom of the file. Add these imports at the top if missing:
`import 'dart:typed_data';` and ensure `rendered_invoice_example.dart` (for
`renderInvoice`) and `invoice_sample.dart` (for `invoiceSchema`) are imported.

Add an export handler to `_PlaygroundHomeState`:

```dart
  /// Export the rendered report as PDF to a picked location (host-owned I/O).
  Future<void> _exportPdf(RenderedReport report) async {
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF document', extensions: <String>['pdf']),
      ],
      suggestedName: 'invoice.pdf',
    );
    if (location == null) return; // user cancelled
    await XFile.fromData(pdf, mimeType: 'application/pdf').saveTo(location.path);
  }
```

Replace the `Positioned.fill( child: JetReportDesigner(...) )` in `build` with:

```dart
        Positioned.fill(
          child: JetReportWorkspace(
            controller: _controller,
            dataSchema: invoiceSchema,
            // Render the LIVE template against the bundled sample data so design
            // edits show up on the next preview entry.
            renderReport: (ReportTemplate template) =>
                renderInvoice(template: template),
            onSaveRequested: _save,
            onOpenRequested: _open,
            onExportPdf: _exportPdf,
            onPrint: (RenderedReport report) =>
                const JetReportPrinter().printReport(report),
          ),
        ),
```

- [ ] **Step 4: Run the consumption test to verify it passes**

Run: `flutter test apps/jet_print_playground/test/app_consumes_library_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify the whole playground suite still passes**

Run: `flutter test apps/jet_print_playground`
Expected: PASS. (`rendered_invoice_example_test.dart` still exercises the
standalone `RenderedInvoiceExample`/`renderInvoice`, which remain in the file as
a documented example — they are no longer wired into `main`.)

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart \
        apps/jet_print_playground/test/app_consumes_library_test.dart
git commit -m "refactor(playground): use JetReportWorkspace for instant mode switching"
```

---

## Task 5: Docs + full-suite verification

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Add a CHANGELOG entry**

Under the top (unreleased / current) heading in `packages/jet_print/CHANGELOG.md`,
add a bullet:

```markdown
- Added `JetReportWorkspace`: a keep-alive designer↔preview workspace. Both
  views stay mounted so switching modes is instant (no canvas re-record), and
  the preview renders behind a loading indicator (`ShadProgress`, overridable
  via `loadingBuilder`) so the first large-data render gives visible feedback
  instead of a frozen frame. Export/print receive the current `RenderedReport`.
```

- [ ] **Step 2: Analyzer + format clean**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && dart analyze packages/jet_print apps/jet_print_playground`
Expected: No issues.

Run: `dart format packages/jet_print/lib/src/designer/jet_report_workspace.dart packages/jet_print/test/designer/jet_report_workspace_test.dart apps/jet_print_playground/lib/main.dart`
Expected: formatting applied / already formatted.

- [ ] **Step 3: Full package + playground suites green**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print && flutter test apps/jet_print_playground`
Expected: PASS, 0 skipped. (Goldens unchanged — this feature adds no report paint.)

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/CHANGELOG.md
git commit -m "docs(workspace): changelog for JetReportWorkspace"
```

---

## Self-review notes (verification the implementer should re-confirm)

- **Spec coverage:** keep-alive (Task 2 `IndexedStack`), instant back-to-design (Task 2 keep-alive test), loading feedback (Task 2 loading test), identity caching + sequence guard (Task 2), export/print on current report (Task 3), playground reference (Task 4), `ShadProgress`/`loadingBuilder` (Task 2/5), single public symbol + `ReportRenderCallback` (Task 1) — all covered.
- **No `pumpAndSettle` while the loading bar is shown** — the helpers pump explicit frames; only after the report lands do they settle.
- **Type consistency:** `ReportRenderCallback = FutureOr<RenderedReport> Function(ReportTemplate)`; `onExportPdf`/`onPrint` are `ValueChanged<RenderedReport>?`; `renderReport` is required. These names match across Tasks 1–4.
- **`controller.rename` exists** (017) and returns a fresh immutable template, which is what makes the identity-based re-render test (Task 2) meaningful.
```
