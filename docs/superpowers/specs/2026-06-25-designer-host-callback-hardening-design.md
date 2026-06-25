# Designer Host-Callback Hardening — Design

**Date:** 2026-06-25
**Component:** `JetReportDesigner` (public designer shell) + `DesignerTopBar` (private).
**Scope:** Designer/UI only. No domain, serialization, or render-engine change; goldens unchanged.

## Problem

`JetReportDesigner` exposes three host callbacks — `onSaveRequested`, `onOpenRequested`,
`onPreviewRequested` — but:

1. There is no error sink. The library does no file I/O itself (FR-022); the host does it
   inside these callbacks. When the host's save/open/preview throws (e.g. a write fails, a
   decode rejects), the designer cannot surface it — and because the host closures are wired
   as `void Function()`, an `async` host callback's rejected Future becomes an *unhandled
   zone error*, invisible to the host.
2. When a host wires **no** callback, the Open/Save buttons still render — disabled but
   present. A host that supports neither still shows dead chrome.

## Goals

- Add an `onError` callback that receives any error (and stack) thrown by a host
  save/open/preview callback — synchronous throw or rejected Future.
- Hide the **Open** and **Save** top-bar buttons entirely when their callback is unwired
  ("available only when assigned"). The File group and its divider collapse when both are
  absent.
- Stay non-breaking: existing hosts (`onSaveRequested` / `onOpenRequested` /
  `onPreviewRequested` names) keep working unchanged.
- Forward `onError` through the `JetReportWorkspace` wrapper (the playground's
  actual consumption path).
- Playground demonstration: wire Open/Save **only** on the Empty manual-testing
  demo; the read-only sample demos pass `null` so their buttons hide — the
  consumer-side proof that hide-when-null works. Export/Print stay on all tabs.

## Non-Goals

- No rename of the existing `*Requested` callbacks (decision: keep them).
- No change to the **Preview** affordance's *placement*: Preview is the center
  Designer↔Preview **mode switch** (`WorkspaceModeSwitch`, wired via
  `onSwitchRequested`), not a trailing action button. It stays always-visible; only its
  invocation is routed through `onError`. Hiding a segment of a segmented toggle is out of
  scope.
- No action-context tag on `onError` (decision: minimal `(error, stack)`).
- No new file I/O in the library.

## Design

### 1. New `onError` property

`packages/jet_print/lib/src/designer/jet_report_designer.dart`:

```dart
/// Invoked when a host Save/Open/Preview callback throws — synchronously or via a
/// rejected Future. Receives the [error] and its [stackTrace]. The library performs
/// no file I/O itself (FR-022), so this surfaces failures the host raised inside the
/// `*Requested` callbacks. Null ⇒ errors propagate as before (no silent swallow).
typedef ReportErrorCallback = void Function(Object error, StackTrace stackTrace);

final ReportErrorCallback? onError;   // new constructor param, optional
```

### 2. Host typedefs widen `void` → `FutureOr<void>`

So the designer can `await` a host callback and catch a rejected Future (not just a sync
throw):

```dart
typedef ReportSaveRequestedCallback    = FutureOr<void> Function(ReportDefinition current);
typedef ReportOpenRequestedCallback    = FutureOr<void> Function();
typedef ReportPreviewRequestedCallback = FutureOr<void> Function(ReportDefinition current);
```

This is **source-compatible**: a closure with a `void` (or `async`) body still satisfies a
`FutureOr<void>` return type. Existing hosts compile unchanged. (`dart:async` is already
imported in `jet_report_designer.dart`.)

### 3. Guarded invocation

The designer wraps every host-callback invocation:

```dart
Future<void> _guard(FutureOr<void> Function() run) async {
  try {
    await run();
  } catch (error, stackTrace) {
    final ReportErrorCallback? onError = widget.onError;
    if (onError != null) {
      onError(error, stackTrace);
    } else {
      rethrow; // preserve today's behavior when no sink is wired
    }
  }
}
```

Wiring at the `DesignerTopBar` bridge (`_buildShell`), all three host callbacks routed
through `_guard`:

```dart
DesignerTopBar(
  onSave: widget.onSaveRequested == null
      ? null
      : () => _guard(() => widget.onSaveRequested!(_controller.definition)),
  onOpen: widget.onOpenRequested == null
      ? null
      : () => _guard(() => widget.onOpenRequested!()),
  onPreview: widget.onPreviewRequested == null
      ? null
      : () => _guard(() => widget.onPreviewRequested!(_controller.definition)),
);
```

Behavior:
- `onError` null → an error from any host callback propagates exactly as it does today
  (sync throws surface at the call site; an unawaited async error stays an unhandled zone
  error). No new swallowing.
- `onError` set → both a synchronous throw and a rejected Future from save/open/preview are
  delivered to `onError(error, stack)` and not rethrown.

### 4. Conditional Open/Save buttons

`packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`, `_actions`:

The File-group buttons are emitted only when their callback is non-null. When **both** are
null the group and its trailing `_Divider` collapse — no leading dead chrome:

```dart
return <Widget>[
  if (widget.onOpen != null)
    _ActionButton(icon: LucideIcons.folderOpen, label: l10n.actionOpen, ...),
  if (widget.onSave != null)
    _ActionButton(icon: LucideIcons.save, label: l10n.actionSave, ...),
  if (widget.onOpen != null || widget.onSave != null) const _Divider(),
  // history group ...
];
```

(The current code emits both buttons unconditionally followed by the History `_Divider`;
that divider becomes the conditional one above so the bar never opens with a leading rule.)

## Components & boundaries

- **`JetReportDesigner`** (public): owns `onError`, owns `_guard`, bridges host callbacks to
  the top bar. Single responsibility: shell composition + host-callback mediation.
- **`DesignerTopBar`** (private): unchanged contract — still takes `onOpen`/`onSave`/`onPreview`
  `VoidCallback?`. New behavior is purely "render the button only when its callback is
  non-null." It does not know about `onError`; the guard lives one layer up. Boundary stays
  clean: the bar renders, the shell mediates.

## Error handling

The whole feature *is* error handling. The one rule: `onError` is the sole sink for host
callback failures; when absent, behavior is identical to today (propagate). The designer
never swallows an error silently.

## Testing

Widget/unit tests in `packages/jet_print/test/designer/`:

1. **`onError` catches sync throw** — host `onSaveRequested` throws synchronously; with
   `onError` wired, the error+stack reach it and nothing propagates.
2. **`onError` catches async rejection** — host `onOpenRequested` is `async` and throws;
   `onError` receives it.
3. **Preview routes through `onError`** — host `onPreviewRequested` throws; `onError` fires.
4. **`onError` null ⇒ propagates** — sync throw with no `onError` surfaces (test via
   `tester.takeException()`), no swallow.
5. **Open hidden when `onOpenRequested` null**; **visible when wired** (find by key/label).
6. **Save hidden when `onSaveRequested` null**; **visible when wired.**
7. **Both null ⇒ File group + leading divider absent** (bar starts at History).
8. **Regression:** existing top-bar / designer tests stay green; **no golden changes**
   (author-time UI only — but the bar's button set changes, so any golden that snapshots the
   top bar with all-null callbacks WILL legitimately change; audit and regenerate only those
   deliberately, noting why).

Verification sweep: `flutter analyze` clean, `dart format` clean, full `flutter test` green
in `packages/jet_print`; playground `flutter analyze && flutter test` green (it consumes the
widened typedefs).

## Risks

1. **Golden snapshots of the top bar** with no callbacks wired will change (Open/Save gone).
   Audit which goldens that is; regenerate deliberately. Bands/page content unaffected.
2. **`void`→`FutureOr<void>` assignability** — verified non-breaking in principle; confirm at
   implementation by compiling the playground against the change before merge.
3. **Tear-down races** — `_guard` is `async`; if the designer is disposed while a host Future
   is in flight, calling `widget.onError` after unmount touches `widget`. Mitigation: read
   `widget.onError` is fine (StatefulWidget `widget` is valid post-dispose for reads); do not
   call `setState`. `_guard` calls no `setState`, so safe.
