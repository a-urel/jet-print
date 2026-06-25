# Designer Host-Callback Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD.

**Goal:** Add an `onError` sink to `JetReportDesigner` that catches host Save/Open/Preview callback failures (sync throw or rejected Future), and hide the Open/Save top-bar buttons when their callback is unwired.

**Architecture:** Widen the three host-callback typedefs `void`→`FutureOr<void>` (non-breaking) so the designer can `await` each and `try/catch` it through a single `_guard`; route Save/Open/Preview through `_guard`. In the top bar, emit the Open/Save buttons (and the leading divider) only when their callbacks are non-null. Forward `onError` through the `JetReportWorkspace` wrapper.

**Tech Stack:** Dart / Flutter, `flutter_test`. Designer + workspace layers only. No domain, serialization, or render-engine change.

## Global Constraints

- Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (`flutter` leaves cwd inside the package).
- Branch is already `designer-host-callbacks`.
- Author-time UI only — **no golden should change** except a full-shell golden that snapshots the top bar built with NO host callbacks (Open/Save now absent). If one changes, confirm it is exactly that case, then regenerate deliberately and note why; never blanket-regenerate.
- Existing public callback names stay (`onSaveRequested` / `onOpenRequested` / `onPreviewRequested`). Non-breaking only.
- `dart:async` is already imported in both `jet_report_designer.dart` and `jet_report_workspace.dart` (for `unawaited`/`FutureOr`), so `FutureOr` needs no new import.
- After each task: `dart format` the touched files and `flutter analyze` clean before committing.

---

## File Map

- `packages/jet_print/lib/src/designer/jet_report_designer.dart` — **modify**: widen 3 typedefs to `FutureOr<void>`; add `ReportErrorCallback` typedef + `onError` field + constructor param + dartdoc; add `_guard`; route the top-bar bridge calls through `_guard`.
- `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` — **modify**: in `_actions`, emit Open/Save `_ActionButton`s and the leading divider conditionally on `widget.onOpen`/`widget.onSave`.
- `packages/jet_print/lib/src/designer/jet_report_workspace.dart` — **modify**: add `onError` field + constructor param, forward to `JetReportDesigner`.
- `packages/jet_print/test/designer/host_callbacks_test.dart` — **new**: `onError` catch (sync/async/preview), null-propagate, button visibility.
- `packages/jet_print/test/designer/top_bar_test.dart` — **modify**: fix the 3 tests that assume Open/Save render with no callbacks (lines ~99, ~230, ~600).

---

## Task 1: `onError` + guarded host-callback invocation

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_designer.dart`
- Test: `packages/jet_print/test/designer/host_callbacks_test.dart` (new)

**Interfaces:**
- Produces: `typedef ReportErrorCallback = void Function(Object error, StackTrace stackTrace);` and a new optional `JetReportDesigner({..., ReportErrorCallback? onError})` field. Typedefs `ReportSaveRequestedCallback` / `ReportOpenRequestedCallback` / `ReportPreviewRequestedCallback` now return `FutureOr<void>`.

- [ ] **Step 1: Write the failing tests.** Create `packages/jet_print/test/designer/host_callbacks_test.dart`:

```dart
// Host-callback hardening: onError catches failures the host raised inside the
// Save/Open/Preview callbacks (sync throw or rejected Future). Drives the public
// JetReportDesigner only; never reaches into src/.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

// The Preview mode-switch segment key (mirrors unified_top_bar.dart).
const Key _previewSegment =
    ValueKey<String>('jet_print.toolbar.mode.preview');

void main() {
  group('JetReportDesigner onError', () {
    testWidgets('catches a synchronous throw from onSaveRequested',
        (WidgetTester tester) async {
      Object? captured;
      StackTrace? capturedStack;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) => throw StateError('boom save'),
          onError: (Object e, StackTrace st) {
            captured = e;
            capturedStack = st;
          },
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(captured, isA<StateError>());
      expect(capturedStack, isNotNull);
      expect(tester.takeException(), isNull,
          reason: 'onError consumed it; nothing propagates');
    });

    testWidgets('catches an async rejection from onOpenRequested',
        (WidgetTester tester) async {
      Object? captured;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: () async => throw StateError('boom open'),
          onError: (Object e, StackTrace _) => captured = e,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('routes a Preview failure through onError',
        (WidgetTester tester) async {
      Object? captured;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onPreviewRequested: (ReportDefinition _) =>
              throw StateError('boom preview'),
          onError: (Object e, StackTrace _) => captured = e,
        ),
      );

      await tester.tap(find.byKey(_previewSegment));
      await tester.pumpAndSettle();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no onError a host throw propagates (not swallowed)',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) => throw StateError('boom'),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(tester.takeException(), isA<StateError>(),
          reason: 'no sink wired ⇒ error surfaces, never silently dropped');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `cd packages/jet_print && flutter test test/designer/host_callbacks_test.dart`
Expected: FAIL — `onError` is not a parameter of `JetReportDesigner` (compile error), and (once that's added) the throws are not yet caught.

- [ ] **Step 3: Widen the host typedefs.** In `jet_report_designer.dart`, change the three typedef return types from `void` to `FutureOr<void>`:

```dart
/// Invoked when the user triggers Save; receives the current [ReportDefinition]
/// to persist. The library performs no file I/O itself (FR-022) — a host encodes
/// it (e.g. via `JetReportFormat.encodeDefinitionJson`) and writes it. May be
/// async; a thrown error or rejected Future is routed to [JetReportDesigner.onError].
typedef ReportSaveRequestedCallback = FutureOr<void> Function(
    ReportDefinition current);

/// Invoked when the user triggers Open; a host reads a definition (e.g. via
/// `JetReportFormat.decodeDefinitionJson`) and calls `controller.open(...)`. May
/// be async; failures route to [JetReportDesigner.onError].
typedef ReportOpenRequestedCallback = FutureOr<void> Function();

/// Invoked when the user triggers Preview; receives the current
/// [ReportDefinition] so a host can render it (e.g. via `JetReportEngine`) and
/// show a `JetReportPreview`. May be async; failures route to
/// [JetReportDesigner.onError].
typedef ReportPreviewRequestedCallback = FutureOr<void> Function(
    ReportDefinition current);

/// Invoked when a host Save/Open/Preview callback throws — synchronously or via
/// a rejected Future. Receives the [error] and its [stackTrace]. The library
/// performs no file I/O itself (FR-022), so this surfaces failures the host
/// raised inside the `*Requested` callbacks. Null ⇒ errors propagate as before
/// (never silently swallowed).
typedef ReportErrorCallback = void Function(Object error, StackTrace stackTrace);
```

- [ ] **Step 4: Add the `onError` field + constructor param.** In the `JetReportDesigner` constructor (after `onPreviewRequested`):

```dart
  const JetReportDesigner({
    super.key,
    this.controller,
    this.initialReport,
    this.onSaveRequested,
    this.onOpenRequested,
    this.onPreviewRequested,
    this.onError,
    this.dataSchema,
    this.fonts = const <JetFontFamily>[],
    this.showBuiltInFonts = true,
  });
```

And the field (after `onPreviewRequested`'s field, ~line 107):

```dart
  /// Invoked when a host Save/Open/Preview callback fails — sync throw or rejected
  /// Future (wired through the top bar). Null ⇒ such errors propagate unchanged.
  final ReportErrorCallback? onError;
```

- [ ] **Step 5: Add `_guard` and route the bridge through it.** In `_JetReportDesignerState`, add the helper (place it near `_handlePropertiesFocusRequest`):

```dart
  /// Runs a host Save/Open/Preview callback, funnelling any failure (a synchronous
  /// throw or a rejected Future) to [JetReportDesigner.onError]. With no sink wired
  /// the error is rethrown, preserving today's propagate-don't-swallow behavior.
  Future<void> _guard(FutureOr<void> Function() run) async {
    try {
      await run();
    } catch (error, stackTrace) {
      final ReportErrorCallback? onError = widget.onError;
      if (onError != null) {
        onError(error, stackTrace);
      } else {
        rethrow;
      }
    }
  }
```

Then rewrite the `DesignerTopBar` bridge in `_buildShell` (currently ~lines 282-288):

```dart
            DesignerTopBar(
              key: _topBarKey,
              // Bridge the host callbacks to the top bar, each funnelled through
              // _guard so a thrown error or rejected Future reaches onError instead
              // of escaping (FR-022 — the library does no file I/O itself).
              onSave: widget.onSaveRequested == null
                  ? null
                  : () => _guard(() => widget.onSaveRequested!(_controller.definition)),
              onOpen: widget.onOpenRequested == null
                  ? null
                  : () => _guard(() => widget.onOpenRequested!()),
              onPreview: widget.onPreviewRequested == null
                  ? null
                  : () => _guard(() => widget.onPreviewRequested!(_controller.definition)),
            ),
```

- [ ] **Step 6: Run the tests to verify they pass.**

Run: `cd packages/jet_print && flutter test test/designer/host_callbacks_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 7: Format, analyze, commit.**

```bash
cd packages/jet_print && dart format lib/src/designer/jet_report_designer.dart test/designer/host_callbacks_test.dart && flutter analyze lib/src/designer/jet_report_designer.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/jet_report_designer.dart packages/jet_print/test/designer/host_callbacks_test.dart
git commit -m "feat(designer): onError sink for host Save/Open/Preview failures

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Hide Open/Save buttons when unwired

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`
- Test: `packages/jet_print/test/designer/host_callbacks_test.dart` (extend), `packages/jet_print/test/designer/top_bar_test.dart` (fix 3 existing tests)

**Interfaces:**
- Consumes: `DesignerTopBar.onOpen` / `.onSave` (`VoidCallback?`, unchanged contract).

- [ ] **Step 1: Write the failing visibility tests.** Append a second group to `host_callbacks_test.dart`:

```dart
  group('Open/Save button visibility', () {
    testWidgets('both absent when no file callbacks are wired',
        (WidgetTester tester) async {
      await pumpDesigner(tester); // const JetReportDesigner(), no callbacks
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(LucideIcons.folderOpen), findsNothing);
      expect(find.byIcon(LucideIcons.save), findsNothing);
    });

    testWidgets('both present when both callbacks are wired',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: () {},
          onSaveRequested: (ReportDefinition _) {},
        ),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('only Save shows when only onSaveRequested is wired',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) {},
        ),
      );
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });
  });
```

Add `import 'package:shadcn_ui/shadcn_ui.dart';` to the test file (for `LucideIcons`).

- [ ] **Step 2: Run to verify failure.**

Run: `cd packages/jet_print && flutter test test/designer/host_callbacks_test.dart -n "Open/Save button visibility"`
Expected: FAIL — buttons currently always render, so "absent" / "only Save" assertions fail.

- [ ] **Step 3: Make the buttons conditional.** In `designer_top_bar.dart`, `_actions`, replace the unconditional Open/Save block plus the History divider that follows it (current lines 100-120) so the File group and its trailing divider appear only when wired:

```dart
    return <Widget>[
      // File group — Open / Save lead the bar, ahead of the editing commands, and
      // each appears only when the host wired its callback ("available only when
      // assigned"). Export is not offered in the designer; it lives in the preview
      // where the artifact exists (017).
      if (widget.onOpen != null)
        _ActionButton(
          icon: LucideIcons.folderOpen,
          label: l10n.actionOpen,
          tooltip: l10n.actionOpenTooltip,
          compact: compact,
          onPressed: widget.onOpen,
        ),
      if (widget.onSave != null)
        _ActionButton(
          icon: LucideIcons.save,
          label: l10n.actionSave,
          tooltip: l10n.actionSaveTooltip,
          compact: compact,
          onPressed: widget.onSave,
        ),
      // Divide the File group off only when it is present, so the bar never opens
      // with a leading rule.
      if (widget.onOpen != null || widget.onSave != null) const _Divider(),

      // History group — wired to the controller, disabled at the ends (US3.4).
      _IconButton(
```

(Note: the `const _Divider()` that previously sat at the top of the History group is now the conditional one above; do NOT leave a second one before `undo`.)

- [ ] **Step 4: Run to verify pass.**

Run: `cd packages/jet_print && flutter test test/designer/host_callbacks_test.dart`
Expected: PASS (visibility + Task-1 groups).

- [ ] **Step 5: Fix the 3 existing top-bar tests that assumed unconditional buttons.** Add two top-level no-op callbacks near the top of `top_bar_test.dart` (after the imports, before `main`):

```dart
void _noOpOpen() {}
void _noOpSave(ReportDefinition _) {}
```

Then:

(a) The "keeps the report title and primary actions" test (~line 92) — wire the callbacks so Open/Save are expected to show:

```dart
    testWidgets('keeps the report title and primary actions', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );

      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      // Export is no longer offered in the designer (it lives in the preview).
      expect(find.text('Export'), findsNothing);
    });
```

(b) The "collapses action labels to icons but keeps name + switch" test (~line 226) — wire the callbacks so the glyphs are expected at compact width:

```dart
    testWidgets('collapses action labels to icons but keeps name + switch',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        size: const Size(700, 760),
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );

      // File-action labels disappear, but their glyphs remain.
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
      expect(find.byIcon(LucideIcons.save), findsOneWidget);
      // The name region and the mode switch stay put (C6.2).
      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.byKey(_modeDesignerKey), findsOneWidget);
      expect(find.byKey(_modePreviewKey), findsOneWidget);
    });
```

(c) The "the right slot shows the editing actions (C5.1)" test (~line 583) — it calls `pumpDesignerWith` (which wires no file callbacks). Replace its pump with a wired designer so the Open/Save assertions still hold:

```dart
    testWidgets('the right slot shows the editing actions (C5.1)', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );
      // Open/save file actions, history, clipboard, zoom, view toggles, arrange.
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(find.byIcon(LucideIcons.redo2), findsOneWidget);
      expect(find.byKey(_cutKey), findsOneWidget);
      expect(find.byKey(_pasteKey), findsOneWidget);
      expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.grid')),
          findsOneWidget);
      expect(
          find.byKey(
              const ValueKey<String>('jet_print.designer.action.arrange')),
          findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
```

(If this test later asserts on the controller `c` returned by `pumpDesignerWith`, it does not — it only checks widget presence — so dropping the return value is safe.)

- [ ] **Step 6: Run the full top-bar + host-callbacks suites.**

Run: `cd packages/jet_print && flutter test test/designer/top_bar_test.dart test/designer/host_callbacks_test.dart`
Expected: PASS. If any OTHER top-bar test fails because it implicitly relied on Open/Save being present with no callbacks, apply the same `_noOpOpen`/`_noOpSave` wiring; do not weaken an assertion to hide a real regression.

- [ ] **Step 7: Format, analyze, commit.**

```bash
cd packages/jet_print && dart format lib/src/designer/layout/designer_top_bar.dart test/designer/host_callbacks_test.dart test/designer/top_bar_test.dart && flutter analyze lib/src/designer/layout/designer_top_bar.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/designer_top_bar.dart packages/jet_print/test/designer/host_callbacks_test.dart packages/jet_print/test/designer/top_bar_test.dart
git commit -m "feat(designer): show Open/Save only when their host callback is wired

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Forward `onError` through `JetReportWorkspace` + full verification

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_workspace.dart`
- Test: `packages/jet_print/test/designer/jet_report_workspace_test.dart` (extend)

**Interfaces:**
- Consumes: `ReportErrorCallback` (Task 1), `JetReportDesigner.onError` (Task 1).

Context — `JetReportWorkspace` (lines ~46-84) already declares `onSaveRequested`/`onOpenRequested` and forwards them to the embedded `JetReportDesigner` (line ~176-183). The playground consumes the *workspace*, so without this forward a host using the workspace cannot reach the new sink.

- [ ] **Step 1: Write the failing test.** In `jet_report_workspace_test.dart`, add (match the file's existing pump/harness style — read it first):

```dart
    testWidgets('forwards onError to the embedded designer',
        (WidgetTester tester) async {
      Object? captured;
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        // Reuse this file's existing app-wrapping helper if it has one; otherwise
        // wrap in the same ShadApp the other tests here use.
        _wrapWorkspace(
          JetReportWorkspace(
            renderReport: _stubRender, // the file's existing render stub
            onSaveRequested: (ReportDefinition _) => throw StateError('boom'),
            onError: (Object e, StackTrace _) => captured = e,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });
```

> Adapt the wrapper/render-stub names to whatever `jet_report_workspace_test.dart` already defines (read the file's top + an existing test). Do NOT invent a render stub if one exists.

- [ ] **Step 2: Run to verify failure.**

Run: `cd packages/jet_print && flutter test test/designer/jet_report_workspace_test.dart -n "forwards onError"`
Expected: FAIL — `onError` is not a parameter of `JetReportWorkspace`.

- [ ] **Step 3: Add `onError` to the workspace and forward it.** In `jet_report_workspace.dart`:

Constructor (alongside `onSaveRequested`/`onOpenRequested`):
```dart
    this.onError,
```
Field (alongside the other callback fields, ~line 76):
```dart
  /// Forwarded to the embedded [JetReportDesigner.onError]: invoked when a host
  /// Save/Open/Preview callback throws or rejects. Null ⇒ errors propagate.
  final ReportErrorCallback? onError;
```
Forward in `build` where it constructs `JetReportDesigner` (~line 176-183):
```dart
        JetReportDesigner(
          // ...existing args...
          onSaveRequested: widget.onSaveRequested,
          onOpenRequested: widget.onOpenRequested,
          onPreviewRequested: _enterPreview,
          onError: widget.onError,
          // ...
        ),
```

(`ReportErrorCallback` resolves via the existing `jet_report_designer.dart` import; confirm that import is present — the file already references `ReportSaveRequestedCallback`, so it is.)

- [ ] **Step 4: Run to verify pass.**

Run: `cd packages/jet_print && flutter test test/designer/jet_report_workspace_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification sweep.**

```bash
cd packages/jet_print
flutter analyze            # clean
dart format --output=none --set-exit-if-changed lib test   # clean
flutter test               # whole package green
```
Expected: all green. **Watch goldens:** if a full-shell golden built with no host callbacks fails because Open/Save are now absent, verify that is the only cause, then regenerate ONLY that golden (`flutter test --update-goldens <path>`) and state it in the commit. Any other golden change → STOP and inspect.

- [ ] **Step 6: Confirm the playground (workspace consumer) still builds.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground
flutter analyze && flutter test
```
Expected: green — the playground's `_save(ReportDefinition) async` / `_open() async` already satisfy the widened `FutureOr<void>` typedefs; the workspace gained only an optional param.

- [ ] **Step 7: Format, analyze, commit.**

```bash
cd packages/jet_print && dart format lib/src/designer/jet_report_workspace.dart test/designer/jet_report_workspace_test.dart && flutter analyze lib/src/designer/jet_report_workspace.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/jet_report_workspace.dart packages/jet_print/test/designer/jet_report_workspace_test.dart
git commit -m "feat(designer): forward onError through JetReportWorkspace

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Playground — gate Open/Save to the Empty demo only

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`
- Test: `apps/jet_print_playground/test/app_consumes_library_test.dart` (fix + extend)

**Interfaces:**
- Consumes: the Task-2 hide-when-null behavior — wiring `onSaveRequested`/`onOpenRequested` to `null` makes the buttons disappear.

Context — every demo tab is a `_DesignerTab` ([main.dart:384](apps/jet_print_playground/lib/main.dart#L384)) built by the `tab()` helper ([main.dart:192-198](apps/jet_print_playground/lib/main.dart#L192-L198)); its `build` wires `onSaveRequested: _save` / `onOpenRequested: _open` unconditionally ([main.dart:515-516](apps/jet_print_playground/lib/main.dart#L515-L516)). The Empty demo is the `'bos'` entry seeded with `emptyDesignDefinition()` ([main.dart:253-258](apps/jet_print_playground/lib/main.dart#L253-L258)). Requirement: only the Empty demo exposes Open/Save; the sample demos pass `null` (so their buttons hide via Task 2). Export/Print stay on all tabs (out of scope).

- [ ] **Step 1: Write the failing test.** In `app_consumes_library_test.dart`, ADD a new test (place after the "Empty tab activates a blank designer" test). It asserts the default (Invoice) onstage tab has Open/Save hidden and the Empty tab shows them:

```dart
  testWidgets(
    'Open/Save show only on the Empty demo (gated host file I/O)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // Launch tab is Invoice — a sample demo: Open/Save are not offered.
      // (find skips Offstage by default, so only the onstage tab counts.)
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);

      // The Empty tab wires the host persistence seam, so both appear.
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run to verify failure.**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart -n "gated host file I/O"`
Expected: FAIL — every tab currently wires Save/Open, so Invoice shows them too (`findsNothing` fails).

- [ ] **Step 3: Add an `enableFileIo` flag to `_DesignerTab`.** In `main.dart`, add the field + ctor param (default `false`):

```dart
  const _DesignerTab({
    required this.fonts,
    required this.seed,
    required this.dataSchema,
    required this.renderReport,
    this.enableFileIo = false,
  });
```
```dart
  /// Whether this tab offers the host Open/Save file actions. Only the Empty
  /// manual-testing tab does; the read-only sample demos leave them unwired so
  /// the designer hides those buttons.
  final bool enableFileIo;
```

- [ ] **Step 4: Thread the flag through the `tab()` helper and turn it on for Empty.** Change the local `tab()` helper ([main.dart:192-198](apps/jet_print_playground/lib/main.dart#L192-L198)):

```dart
    _DesignerTab tab(ReportDefinition seed, JetDataSchema schema,
            RenderedReport Function(ReportDefinition) render,
            {bool fileIo = false}) =>
        _DesignerTab(
            fonts: widget.fonts,
            seed: seed,
            dataSchema: schema,
            renderReport: render,
            enableFileIo: fileIo);
```

And the Empty (`'bos'`) demo body passes `fileIo: true`:

```dart
      (
        value: 'bos',
        icon: LucideIcons.squareDashed,
        body: tab(emptyDesignDefinition(), invoiceSchema,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts),
            fileIo: true),
      ),
```

- [ ] **Step 5: Gate the callbacks in `_DesignerTab.build`.** In the `JetReportWorkspace` ([main.dart:515-516](apps/jet_print_playground/lib/main.dart#L515-L516)):

```dart
      onSaveRequested: widget.enableFileIo ? _save : null,
      onOpenRequested: widget.enableFileIo ? _open : null,
```

(Leave `onExportPdf` / `onPrint` unchanged — they stay on every tab.)

- [ ] **Step 6: Fix the existing "wires the Save/Open callbacks" test.** That test ([app_consumes_library_test.dart:140-156](apps/jet_print_playground/test/app_consumes_library_test.dart#L140-L156)) reads the onstage (Invoice) workspace and asserts Save/Open are wired — now they are null there. Update it to assert the gating: Invoice unwired, Empty wired.

```dart
  testWidgets(
    'only the Empty demo wires the Save/Open callbacks (FR-022)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // The launch (Invoice) tab is a read-only sample: Save/Open are NOT wired.
      JetReportWorkspace onstage() =>
          tester.widget<JetReportWorkspace>(find.byType(JetReportWorkspace));
      expect(onstage().controller, isNotNull,
          reason: 'the app owns the controller on every tab');
      expect(onstage().onSaveRequested, isNull);
      expect(onstage().onOpenRequested, isNull);

      // The Empty tab wires the host persistence seam.
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();
      expect(onstage().onSaveRequested, isNotNull,
          reason: 'Save is wired on the Empty tab');
      expect(onstage().onOpenRequested, isNotNull,
          reason: 'Open is wired on the Empty tab');
    },
  );
```

- [ ] **Step 7: Run to verify pass.**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart`
Expected: PASS (the new gating test + the rewritten FR-022 test + the unchanged others).

- [ ] **Step 8: Full playground sweep.**

```bash
cd apps/jet_print_playground
flutter analyze            # clean
dart format --output=none --set-exit-if-changed lib test   # clean
flutter test               # green — fix any OTHER test that assumed Save/Open on a sample tab with the same gating assertion
```

- [ ] **Step 9: Format, analyze, commit.**

```bash
cd apps/jet_print_playground && dart format lib/main.dart test/app_consumes_library_test.dart && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/test/app_consumes_library_test.dart
git commit -m "feat(playground): offer Open/Save only on the Empty demo

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:**
  - "Add `onError`" → Task 1 (typedef, field, `_guard`).
  - "Wrap host callbacks in try/catch; Preview routed too" → Task 1 Step 5 (`_guard` on Save/Open/Preview) + test 3.
  - "`onError` null ⇒ propagate, no swallow" → Task 1 Step 5 (`rethrow`) + test 4.
  - "Async failures caught" → Task 1 Step 3 (typedef widening) + test 2.
  - "Hide Open/Save when unwired; group + divider collapse" → Task 2 Step 3 + visibility tests.
  - "Preview mode-switch stays visible" → unchanged (only its invocation is guarded); the `_previewSegment` tap in Task 1 test 3 proves it is still present + wired.
  - "Non-breaking; minimal `(error, stack)`" → typedef widening (source-compatible) + `ReportErrorCallback` is exactly `(Object, StackTrace)`.
  - "Workspace consumer reachable" → Task 3.
  - "Playground: only the Empty demo supports Open/Save" → Task 4 (`enableFileIo` flag, gated callbacks, fixed FR-022 test).
- **Placeholder scan:** none — every code step shows full code; the one adaptation note (Task 3 Step 1 render-stub/wrapper names) is explicitly "use what the file already defines," not a TODO.
- **Type consistency:** `ReportErrorCallback = void Function(Object, StackTrace)` used identically in designer field, `_guard` catch, workspace field, and all tests. `_guard` takes `FutureOr<void> Function()`, matching the widened typedefs. Button predicates read `widget.onOpen`/`widget.onSave` (`VoidCallback?`), matching `DesignerTopBar`'s existing fields.
- **Risks:** (1) full-shell no-callback golden may legitimately change (Task 3 Step 5 handles it). (2) `_guard` is async and calls no `setState`, so a callback completing post-dispose only reads `widget.onError` (valid) — no unmount crash. (3) Other top-bar tests implicitly depending on unconditional Open/Save are caught by Task 2 Step 6's full-suite run.
