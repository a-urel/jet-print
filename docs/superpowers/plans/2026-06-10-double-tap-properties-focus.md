# Double-Tap Focuses Properties Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-tapping any report object on the designer canvas selects it, brings the right panel to the Properties tab (opening the narrow-layout overlay if collapsed), and moves keyboard focus into the Text field (text elements) or X field (everything else); the inline text editor is removed entirely.

**Architecture:** A one-shot "pending properties focus" flag on `JetReportDesignerController` (`requestPropertiesFocus` / `pendingPropertiesFocus` peek / `takePropertiesFocus` consume). The canvas raises it on double-tap; the shell (narrow overlay) and right panel (tab switch) *peek*; the Properties panel *consumes* it post-frame and focuses the target field via externally-owned `FocusNode`s. Spec: `docs/superpowers/specs/2026-06-10-double-tap-properties-focus-design.md`.

**Tech Stack:** Flutter, shadcn_ui 0.54 (`ShadTabs` + `ShadTabsController` — note `ShadTabs` asserts exactly ONE of `value`/`controller` is given), `flutter_test`.

**Working context:** Repo `/Users/ahmeturel/Projects/oss/jet-print`, base branch `012-export-support` (the spec commit `dc12013` lives there). All `flutter` commands run inside `packages/jet_print`; always use a subshell `(cd packages/jet_print && ...)` so git commands keep running from the repo root (flutter leaves the cwd inside the package).

**Existing tests that must stay green:** `test/designer/right_panel_tabs_test.dart` (default tab is Data Source), `test/designer/properties_editor_test.dart`, `test/designer/panels/cross_panel_sync_test.dart`, `test/designer/responsive_collapse_test.dart`. The full suite is currently 851 tests, 0 skips.

---

### Task 1: Controller — the one-shot properties-focus intent

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (insert after `_setSelection`, around line 119)
- Test: `packages/jet_print/test/designer/controller/properties_focus_request_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/properties_focus_request_test.dart`:

```dart
// Double-tap → Properties focus: the controller carries an ephemeral one-shot
// UI intent (a flag, not a counter, so it survives until the panel that must
// consume it mounts — e.g. the narrow-layout overlay opening first).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('requestPropertiesFocus raises the pending flag and notifies', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    expect(c.pendingPropertiesFocus, isFalse);
    c.requestPropertiesFocus();
    expect(c.pendingPropertiesFocus, isTrue);
    expect(notifications, 1);
  });

  test('takePropertiesFocus consumes the flag once, without notifying', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    expect(c.takePropertiesFocus(), isFalse); // nothing pending
    c.requestPropertiesFocus();
    expect(c.takePropertiesFocus(), isTrue); // consume
    expect(c.takePropertiesFocus(), isFalse); // one-shot
    expect(c.pendingPropertiesFocus, isFalse);
    expect(notifications, 1); // only the request notified, not the take
  });

  test('a second request while one is pending still notifies listeners', () {
    // The shell/right panel react per-notification; a double-tap while a prior
    // request is somehow unconsumed must still bring the panel forward.
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    c.requestPropertiesFocus();
    c.requestPropertiesFocus();
    expect(notifications, 2);
    expect(c.pendingPropertiesFocus, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `(cd packages/jet_print && flutter test test/designer/controller/properties_focus_request_test.dart)`
Expected: FAIL to compile — `pendingPropertiesFocus` / `requestPropertiesFocus` / `takePropertiesFocus` are not defined.

- [ ] **Step 3: Implement the controller members**

In `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`, insert after the `_setSelection` method (after line 119, before the `// --- Creation ---` section):

```dart
  // --- Properties-focus intent -----------------------------------------------
  // An ephemeral UI signal, not model state: never serialized, never a history
  // entry, untouched by undo/redo/open.

  bool _pendingPropertiesFocus = false;

  /// Whether a [requestPropertiesFocus] is awaiting consumption. Long-lived
  /// designer chrome (the shell, the right panel) peeks at this to bring the
  /// Properties inspector forward without claiming the event.
  bool get pendingPropertiesFocus => _pendingPropertiesFocus;

  /// Asks the designer chrome to bring the Properties inspector forward and
  /// move keyboard focus into the selected element's most relevant field (the
  /// canvas calls this on a double-tap). The inspector consumes the request
  /// via [takePropertiesFocus].
  void requestPropertiesFocus() {
    _pendingPropertiesFocus = true;
    notifyListeners();
  }

  /// Consumes a pending Properties-focus request: returns whether one was
  /// pending and clears it. Called once per request by the Properties
  /// inspector after it moves keyboard focus. Does not notify.
  bool takePropertiesFocus() {
    final bool pending = _pendingPropertiesFocus;
    _pendingPropertiesFocus = false;
    return pending;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `(cd packages/jet_print && flutter test test/designer/controller/properties_focus_request_test.dart)`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart packages/jet_print/test/designer/controller/properties_focus_request_test.dart
git commit -m "Add one-shot properties-focus intent to the designer controller"
```

---

### Task 2: Right panel — switch to the Properties tab on a focus request

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/designer_right_panel.dart` (stateless → stateful with a `ShadTabsController`)
- Test: `packages/jet_print/test/designer/properties_focus_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/properties_focus_test.dart`:

```dart
// Double-tap → Properties focus: a requestPropertiesFocus() brings the right
// panel to the Properties tab (this file grows shell-overlay and field-focus
// coverage in later tasks). Exercised through the public entry point only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

final Finder _xField =
    find.byKey(const ValueKey<String>('jet_print.designer.properties.field.x'));
final Finder _textField = find.byKey(
    const ValueKey<String>('jet_print.designer.properties.field.text'));

void main() {
  testWidgets('a focus request switches the right panel to the Properties tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    // Data Source is the default tab: no inspector fields are present.
    expect(_xField, findsNothing);

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    // The Properties tab is now active, showing the element inspector.
    expect(_xField, findsOneWidget);
    expect(_textField, findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart)`
Expected: FAIL — `expect(_xField, findsOneWidget)` finds nothing (the tab never switches).

- [ ] **Step 3: Rewrite DesignerRightPanel as a stateful widget**

Replace the entire body of `packages/jet_print/lib/src/designer/layout/designer_right_panel.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';
import 'panels/data_source_panel.dart';
import 'panels/outline_panel.dart';
import 'panels/properties_panel.dart';

/// The right context panel: a [ShadTabs] hosting the three designer context
/// panels — **Data Source**, **Outline**, **Properties** — in that fixed order,
/// with Data Source active by default (FR-004/005/006).
///
/// `ShadTabs` renders exactly one body at a time and highlights the active tab.
/// `maintainState: false` makes the inactive bodies leave the tree entirely
/// (rather than merely being hidden), giving an unambiguous "exactly one panel
/// visible" guarantee. `expandContent: true` lets the active body fill the
/// panel's height so each panel scrolls within its own bounds (FR-010). Captions
/// come from [JetPrintLocalizations].
///
/// The tab selection is owned by a [ShadTabsController] so a pending
/// `requestPropertiesFocus` (a canvas double-tap) can bring the Properties tab
/// forward — both while mounted (listener) and at mount time (the narrow-layout
/// overlay mounts this panel only after the request fired).
class DesignerRightPanel extends StatefulWidget {
  /// Creates the right tabbed panel. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerRightPanel({super.key});

  @override
  State<DesignerRightPanel> createState() => _DesignerRightPanelState();
}

class _DesignerRightPanelState extends State<DesignerRightPanel> {
  /// Stable tab identifiers (private; never exported per the API contract).
  static const String _dataSource = 'dataSource';
  static const String _outline = 'outline';
  static const String _properties = 'properties';

  final ShadTabsController<String> _tabs =
      ShadTabsController<String>(value: _dataSource);

  /// The designer controller we are subscribed to for focus requests.
  JetReportDesignerController? _bound;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final JetReportDesignerController controller =
        DesignerScope.of(context, listen: false);
    if (!identical(controller, _bound)) {
      _bound?.removeListener(_handleControllerChange);
      _bound = controller;
      _bound!.addListener(_handleControllerChange);
      // A request that fired before this panel existed (the narrow-layout
      // overlay opens first, then mounts this panel) is honored at mount.
      if (controller.pendingPropertiesFocus) _tabs.select(_properties);
    }
  }

  /// Peeks (never consumes — the Properties panel does) at a pending focus
  /// request and brings the Properties tab forward.
  void _handleControllerChange() {
    if (_bound?.pendingPropertiesFocus ?? false) _tabs.select(_properties);
  }

  @override
  void dispose() {
    _bound?.removeListener(_handleControllerChange);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return ColoredBox(
      color: theme.colorScheme.card,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ShadTabs<String>(
          controller: _tabs,
          // Natural-width, horizontally scrollable tab bar: equal-thirds tabs
          // would clip captions like "Data Source" (and longer translations such
          // as German "Eigenschaften") in a narrow panel. Scrollable keeps every
          // caption fully legible at any panel width and in any locale.
          scrollable: true,
          tabs: <ShadTab<String>>[
            ShadTab<String>(
              value: _dataSource,
              expandContent: true,
              maintainState: false,
              content: const DataSourcePanel(),
              child: Text(l10n.tabDataSource),
            ),
            ShadTab<String>(
              value: _outline,
              expandContent: true,
              maintainState: false,
              content: const OutlinePanel(),
              child: Text(l10n.tabOutline),
            ),
            ShadTab<String>(
              value: _properties,
              expandContent: true,
              maintainState: false,
              content: const PropertiesPanel(),
              child: Text(l10n.tabProperties),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note the `value: _dataSource` parameter on `ShadTabs` is **removed** — the widget asserts `(value != null) ^ (controller != null)`; passing both throws.

- [ ] **Step 4: Run the new test and the existing tab/panel tests**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart test/designer/right_panel_tabs_test.dart test/designer/properties_editor_test.dart test/designer/panels/cross_panel_sync_test.dart)`
Expected: ALL PASS (default tab still Data Source; manual tab clicks still work).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/designer_right_panel.dart packages/jet_print/test/designer/properties_focus_test.dart
git commit -m "Right panel: bring the Properties tab forward on a focus request"
```

---

### Task 3: Shell — open the narrow-layout overlay on a focus request

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_designer.dart` (`_JetReportDesignerState`)
- Test: `packages/jet_print/test/designer/properties_focus_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Append to `main()` in `packages/jet_print/test/designer/properties_focus_test.dart`:

```dart
  testWidgets(
      'narrow layout: a focus request opens the overlay on the Properties tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester, size: kNarrowSize);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    // Collapsed: the right panel is not in the tree at all, only its rail.
    expect(find.byKey(kRightPanelKey), findsNothing);
    expect(find.byKey(kRightPanelRailKey), findsOneWidget);

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    // The overlay opened and mounted straight onto the Properties tab.
    expect(find.byKey(kRightPanelKey), findsOneWidget);
    expect(_xField, findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart)`
Expected: the new test FAILS at `expect(find.byKey(kRightPanelKey), findsOneWidget)` — the overlay never opens. (The Task 2 test still passes.)

- [ ] **Step 3: Wire the shell listener**

In `packages/jet_print/lib/src/designer/jet_report_designer.dart`, make four edits inside `_JetReportDesignerState`:

(a) Replace `initState` / `didUpdateWidget` / `_adoptController` / `dispose` (lines 108–137) with:

```dart
  @override
  void initState() {
    super.initState();
    _adoptController();
  }

  @override
  void didUpdateWidget(JetReportDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_handlePropertiesFocusRequest);
      if (_ownsController) _controller.dispose();
      _adoptController();
    }
  }

  void _adoptController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = JetReportDesignerController(template: widget.initialReport);
      _ownsController = true;
    }
    _controller.addListener(_handlePropertiesFocusRequest);
  }

  @override
  void dispose() {
    _controller.removeListener(_handlePropertiesFocusRequest);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
```

(b) Below the `bool _rightOpen = false;` field (line 160), add:

```dart
  /// Whether the last laid-out main area was the wide (≥ breakpoint) variant;
  /// written during build, read by [_handlePropertiesFocusRequest] so a focus
  /// request only opens the overlay when the panel is actually collapsed.
  bool _lastLayoutWide = true;

  /// Opens the collapsed narrow-layout overlay when a Properties-focus request
  /// arrives, so the panel that must consume it can mount. Peeks only — the
  /// Properties panel consumes the request.
  void _handlePropertiesFocusRequest() {
    if (_lastLayoutWide || _rightOpen) return;
    if (!_controller.pendingPropertiesFocus) return;
    setState(() => _rightOpen = true);
  }
```

(c) In `_buildShell`, inside the inner `LayoutBuilder` (line 217), record the layout variant:

```dart
                final bool wide = constraints.maxWidth >= _breakpoint;
                _lastLayoutWide = wide;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart test/designer/responsive_collapse_test.dart test/designer/jet_report_designer_test.dart)`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/jet_report_designer.dart packages/jet_print/test/designer/properties_focus_test.dart
git commit -m "Shell: open the narrow-layout overlay on a properties-focus request"
```

---

### Task 4: Properties panel — consume the request and focus the target field

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`
- Test: `packages/jet_print/test/designer/properties_focus_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Add this helper above `main()` in `packages/jet_print/test/designer/properties_focus_test.dart`:

```dart
/// Whether the inspector input under [field] holds keyboard focus. ShadInput
/// hosts an EditableText; its focus node reflects where typing goes.
bool _hasFocus(WidgetTester tester, Finder field) {
  final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)));
  return editable.focusNode.hasFocus;
}
```

Append to `main()`:

```dart
  testWidgets(
      'a focus request lands keyboard focus in the Text field of a text element '
      'and is consumed', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, _textField), isTrue);
    expect(controller.pendingPropertiesFocus, isFalse); // consumed
  });

  testWidgets('a focus request targets the X field for a non-text element',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.shape,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, _xField), isTrue);
    expect(controller.pendingPropertiesFocus, isFalse);
  });

  testWidgets('narrow layout: the overlay mount also lands field focus',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester, size: kNarrowSize);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, _textField), isTrue);
    expect(controller.pendingPropertiesFocus, isFalse);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart)`
Expected: the three new tests FAIL on `_hasFocus(...) == isTrue` (no focus moves) — earlier tests still pass.

- [ ] **Step 3: Make PropertiesPanel stateful and wire the focus nodes**

In `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`:

(a) Replace the `PropertiesPanel` class declaration and `build` (lines 37–72) with a stateful widget; every existing helper method (`_elementInspector`, `_unresolved`, `_bandInspector`, `_reportInspector`, `_find`) moves **unchanged** into `_PropertiesPanelState`:

```dart
class PropertiesPanel extends StatefulWidget {
  /// Creates the Properties panel body. Private to the library.
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  /// Externally-owned focus nodes for the two double-tap focus targets, so a
  /// pending `requestPropertiesFocus` can land keyboard focus (the fields fall
  /// back to private nodes when none is supplied).
  final FocusNode _xFocus = FocusNode(debugLabel: 'jet_print.properties.x');
  final FocusNode _textFocus =
      FocusNode(debugLabel: 'jet_print.properties.text');

  @override
  void dispose() {
    _xFocus.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// Consumes a pending properties-focus request after this frame settles (so
  /// the target field exists even when the tab body mounted this same frame)
  /// and moves keyboard focus to the Text field (text element) or the X field
  /// (any other element). One-shot: `takePropertiesFocus` clears the flag, so
  /// ordinary rebuilds never re-steal focus. A non-single selection just
  /// consumes the request — no crash, no stuck flag.
  void _schedulePendingFocus(JetReportDesignerController controller) {
    if (!controller.pendingPropertiesFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.takePropertiesFocus()) return;
      final String? id = controller.selection.singleOrNull;
      if (id == null) return;
      final ReportElement? element = _find(controller, id);
      if (element == null) return;
      (element is TextElement ? _textFocus : _xFocus).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final JetDataSchema? schema = DesignerSchemaScope.of(context);
    final selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    _schedulePendingFocus(controller);

    final List<Widget> children;
    if (selection.isReport) {
      children = _reportInspector(controller, theme, l10n);
    } else if (selection.bandIndex case final int bandIndex) {
      children = _bandInspector(controller, bandIndex, theme, l10n);
    } else if (selection.singleOrNull case final String id
        when _find(controller, id) != null) {
      children = _elementInspector(
          controller, _find(controller, id)!, theme, l10n, schema);
    } else {
      return KeyedSubtree(
        key: const ValueKey<String>('$_p.empty'),
        child: _EmptyState(count: selection.length),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // ... the five helper methods move here unchanged, except the two edits in (b) ...
}
```

(b) Inside the moved `_elementInspector`, pass the nodes to the two target fields. The X field (currently lines 92–97) becomes:

```dart
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.x'),
              prefix: LucideIcons.arrowRight,
              value: b.x,
              focusNode: _xFocus,
              onCommit: (double v) => controller.setGeometry(id, x: v),
            ),
```

The Text field (currently lines 136–140) becomes:

```dart
        _TextField(
          fieldKey: const ValueKey<String>('$_p.field.text'),
          value: element.text,
          focusNode: _textFocus,
          onCommit: (String v) => controller.setText(id, v),
        ),
```

(c) Give `_NumberField` an optional external node. Replace the `_NumberField` widget + state (lines 390–465) with:

```dart
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.fieldKey,
    required this.prefix,
    required this.value,
    required this.onCommit,
    this.focusNode,
  });

  final Key fieldKey;
  final IconData prefix;
  final double value;
  final ValueChanged<double> onCommit;

  /// An externally-owned focus node (the panel's double-tap focus target);
  /// null ⇒ the field owns a private one.
  final FocusNode? focusNode;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  FocusNode? _ownFocus;

  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    // Reflect a model change made elsewhere, but never clobber active typing.
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final double? parsed = double.tryParse(_controller.text.trim());
    if (parsed != null) {
      widget.onCommit(parsed);
    } else {
      _controller.text = _format(widget.value); // reject unparseable input
    }
  }

  void _bump(double delta) => widget.onCommit(widget.value + delta);

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      onSubmitted: (_) => _commit(),
      leading: Icon(widget.prefix, size: 14, color: colors.mutedForeground),
      trailing: _Stepper(
        onIncrement: () => _bump(1),
        onDecrement: () => _bump(-1),
      ),
    );
  }
}
```

(d) Same treatment for `_TextField` (lines 468–525):

```dart
class _TextField extends StatefulWidget {
  const _TextField({
    required this.fieldKey,
    required this.value,
    required this.onCommit,
    this.focusNode,
  });

  final Key fieldKey;
  final String value;
  final ValueChanged<String> onCommit;

  /// An externally-owned focus node (the panel's double-tap focus target);
  /// null ⇒ the field owns a private one.
  final FocusNode? focusNode;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  FocusNode? _ownFocus;

  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _controller.text != widget.value) {
      widget.onCommit(_controller.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      onSubmitted: widget.onCommit,
    );
  }
}
```

(`_BindingField` is never a double-tap target — leave it untouched. YAGNI.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `(cd packages/jet_print && flutter test test/designer/properties_focus_test.dart test/designer/properties_editor_test.dart test/designer/properties_binding_editor_test.dart test/designer/panels/cross_panel_sync_test.dart)`
Expected: ALL PASS (existing field commit/blur behavior unchanged).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/properties_focus_test.dart
git commit -m "Properties panel: consume the focus request and focus Text/X field"
```

---

### Task 5: Canvas — double-tap requests properties focus; remove inline editing

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`
- Delete: `packages/jet_print/lib/src/designer/canvas/inline_text_editor.dart`
- Delete: `packages/jet_print/test/designer/canvas/inline_text_edit_test.dart`
- Test: `packages/jet_print/test/designer/canvas/double_tap_properties_focus_test.dart` (create)

- [ ] **Step 1: Write the failing end-to-end test**

Create `packages/jet_print/test/designer/canvas/double_tap_properties_focus_test.dart`:

```dart
// Double-tapping a report object brings the Properties inspector forward and
// focuses its most relevant field — Text for a text element, X otherwise.
// In-place editing is gone (the Properties panel is the only text editor).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

final Finder _xField =
    find.byKey(const ValueKey<String>('jet_print.designer.properties.field.x'));
final Finder _textField = find.byKey(
    const ValueKey<String>('jet_print.designer.properties.field.text'));

String _textOf(JetReportDesignerController c, String id) => (c.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement e) => e.id == id) as TextElement)
    .text;

bool _hasFocus(WidgetTester tester, Finder field) {
  final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)));
  return editable.focusNode.hasFocus;
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'double-tapping a text element focuses the Properties Text field; the '
      'edit commits and is undoable', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(_textOf(controller, id), 'Text'); // default content

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    // No inline editor anymore; the Properties tab took over.
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.inlineTextEditor')),
        findsNothing);
    expect(controller.selection.singleOrNull, id);
    expect(_hasFocus(tester, _textField), isTrue);

    // The focused field edits the element's text, undoably (FR coverage that
    // the removed inline-editor test used to provide).
    await tester.enterText(_textField, 'Invoice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_textOf(controller, id), 'Invoice');
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_textOf(controller, id), 'Text');
  });

  testWidgets('double-tapping a shape element focuses the X field',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.shape,
        bandIndex: 1, at: const JetOffset(40, 30));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    expect(_hasFocus(tester, _xField), isTrue);
  });

  testWidgets('a single tap selects but never switches the right panel tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    controller.clearSelection();
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    // Let the manual double-tap window (300 ms) lapse.
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    expect(controller.selection.singleOrNull, id); // selected…
    expect(_xField, findsNothing); // …but still on the Data Source tab
    expect(controller.pendingPropertiesFocus, isFalse);
  });

  testWidgets(
      'narrow layout: a double-tap opens the overlay and focuses the field',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester, size: kNarrowSize);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(find.byKey(kRightPanelKey), findsNothing); // collapsed to the rail

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    expect(find.byKey(kRightPanelKey), findsOneWidget);
    expect(_hasFocus(tester, _textField), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `(cd packages/jet_print && flutter test test/designer/canvas/double_tap_properties_focus_test.dart)`
Expected: FAIL — the first test finds the inline editor (`findsNothing` assertion fails) and/or `_hasFocus` is false; the shape test fails (double-tap currently ignores non-text elements).

- [ ] **Step 3: Rewire the canvas and delete the inline editor**

All edits in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`:

(a) Delete the import (line 37): `import 'inline_text_editor.dart';`

(b) Delete the `_editingId` field and its doc (lines 106–107), and update the double-tap doc (lines 109–111) to:

```dart
  /// Manual double-tap detection (avoids a DoubleTapGestureRecognizer, which
  /// would delay single-tap select). Tracks the last tap's position + a reset
  /// timer; a second tap near it on any element brings the Properties
  /// inspector forward for it.
```

(c) In `_handleTapDown`, replace the double-tap branch (lines 255–265) with:

```dart
    // Manual double-tap: a second tap near the first brings the Properties
    // inspector forward for the tapped element — without a
    // DoubleTapGestureRecognizer delaying the single-tap select above.
    final bool near = _lastTapPosition != null &&
        (_lastTapPosition! - localPosition).distance < 24;
    if (near) {
      _doubleTapTimer?.cancel();
      _lastTapPosition = null;
      controller.requestPropertiesFocus();
      return;
    }
```

(d) Delete the inline-editor render block in `_buildPage` — the `if (_editingId case final String editId)` chain through the closing of its `Positioned(...)` (lines 716–738, including the `// Inline text editor over the element being double-click-edited.` comment).

(e) Run `grep -n "_findElement" packages/jet_print/lib/src/designer/canvas/design_canvas.dart`. Its only call sites were the two just removed — delete the now-dead `_findElement` method (around line 441). If `flutter analyze` then reports unused imports (e.g. `text_element.dart`), remove them.

(f) Delete the two files:

```bash
git rm packages/jet_print/lib/src/designer/canvas/inline_text_editor.dart packages/jet_print/test/designer/canvas/inline_text_edit_test.dart
```

(g) Sanity check nothing else references the editor (expect no output):

```bash
grep -rn "InlineTextEditor\|inline_text_editor\|inlineTextEditor" packages/jet_print/lib packages/jet_print/test packages/jet_print/example apps/jet_print_playground/lib apps/jet_print_playground/test 2>/dev/null
```

- [ ] **Step 4: Run the canvas tests and analyzer**

Run: `(cd packages/jet_print && flutter analyze && flutter test test/designer/canvas/ test/designer/properties_focus_test.dart test/designer/interaction/)`
Expected: analyzer clean; ALL tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A packages/jet_print/lib/src/designer/canvas packages/jet_print/test/designer/canvas
git commit -m "Canvas: double-tap focuses the Properties pane; remove inline text editing"
```

---

### Task 6: Docs, changelog, full verification

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_designer.dart` (class dartdoc, lines 34–39)
- Modify: `packages/jet_print/CHANGELOG.md` (Unreleased section)

- [ ] **Step 1: Update the shell dartdoc**

In `packages/jet_print/lib/src/designer/jet_report_designer.dart`, the class doc paragraph (lines 34–39) currently reads "…copy/paste, nudge, delete, and inline-edit text — every edit against…". Replace that paragraph with:

```dart
/// The center surface is a live WYSIWYG canvas: authors drag toolbox element
/// types onto bands, then select, move, resize, align, multi-select, reorder,
/// copy/paste, nudge, and delete — a double-tap on any element jumps to its
/// Properties inspector with the most relevant field focused. Every edit runs
/// against an in-memory [ReportTemplate] held by a
/// [JetReportDesignerController], with unlimited session undo/redo. Property
/// editing this iteration is geometry + text only (the full per-type suite is
/// deferred).
```

- [ ] **Step 2: Add the CHANGELOG entry**

In `packages/jet_print/CHANGELOG.md`, under `## Unreleased`, add a `### Changed` section (after the existing `### Added` block; create it if a merge reordered things) with:

```markdown
### Changed

- **Designer: double-tap now opens the Properties inspector (in-place editing
  removed).** Double-tapping any element on the canvas selects it, brings the
  right panel to the Properties tab (expanding the collapsed narrow-layout
  overlay first when needed), and moves keyboard focus into the most relevant
  field — Text for a text element, X for everything else. The inline
  double-click text editor is gone; the Properties panel is the single
  text-editing surface. New `JetReportDesignerController` members back this:
  `requestPropertiesFocus()` raises a one-shot UI intent,
  `pendingPropertiesFocus` peeks at it, and `takePropertiesFocus()` consumes
  it (the designer chrome wires these automatically; hosts may call
  `requestPropertiesFocus()` to deep-link their own UI into the inspector).
```

- [ ] **Step 3: Format, analyze, and run the full suite**

Run: `(cd packages/jet_print && dart format lib test && flutter analyze && flutter test)`
Expected: format makes no unexpected changes; analyzer clean; full suite passes (≈855 tests: 851 − 2 removed + ~7 added, 0 skips).

- [ ] **Step 4: Commit**

```bash
git add packages/jet_print/lib/src/designer/jet_report_designer.dart packages/jet_print/CHANGELOG.md
git commit -m "Docs + changelog for double-tap properties focus"
```

---

## Verification checklist (post-plan)

- Double-tap text element (wide): Properties tab + Text field focused. ✅ Task 5 test 1
- Double-tap non-text element: X field focused. ✅ Task 5 test 2
- Single tap never switches tabs. ✅ Task 5 test 3
- Narrow layout: overlay opens + field focused. ✅ Task 4 test 3, Task 5 test 4
- Inline editor fully removed (code, render block, file, old test). ✅ Task 5
- Text edits via panel commit + undo. ✅ Task 5 test 1
- Existing suites (tabs default, properties editing, cross-panel sync, responsive collapse) untouched. ✅ Tasks 2–5 run them
