# Demo Left-Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the playground's top horizontal `ShadTabs` demo strip with a left navigation — a persistent fixed sidebar on wide screens and a hamburger-triggered `Scaffold` drawer on narrow screens.

**Architecture:** Extract the demo list into a stateless, reusable `DemoNavList` widget (its own file) driven by a `DemoNavItem` view of the existing registry. The shell wraps in a `Scaffold`: the drawer always holds the nav (so the body never remounts), while a `LayoutBuilder` at 600dp shows either a fixed sidebar (wide) or a hamburger top bar (narrow). The heavy `IndexedStack` of designer bodies keeps a stable `GlobalKey` so it survives the wide⇄narrow swap.

**Tech Stack:** Flutter, `shadcn_ui` ^0.54.0 (`ShadButton`, `ShadApp`, `ShadTheme`, `LucideIcons`), Material `Scaffold`/`Drawer` for the hamburger drawer.

## Global Constraints

- Package: `apps/jet_print_playground` (`publish_to: 'none'`). Dart SDK `^3.6.0`.
- UI chrome stays `shadcn_ui` ^0.54.0. **No new dependencies.**
- **Preserve edit-survival:** all demo bodies stay mounted in one `IndexedStack`; switching changes only `index`. A designer must never remount on a nav switch (guarded by `app_consumes_library_test.dart`'s "SAME State" test).
- Responsive breakpoint is `_narrowWidth = 600` via `LayoutBuilder`. **No `MediaQuery`.**
- The two hardcoded labels `'Symbologies'` and `'Custom'` stay hardcoded (not l10n) — out of scope.

---

## File Structure

- **Create** `apps/jet_print_playground/lib/demo_nav_list.dart` — public `DemoNavItem` (value/icon/label) + public stateless `DemoNavList` (the shared selectable list, no chrome). One responsibility: render a vertical list of selectable demo entries.
- **Create** `apps/jet_print_playground/test/demo_nav_list_test.dart` — unit test for `DemoNavList` in isolation.
- **Modify** `apps/jet_print_playground/lib/main.dart` — `_PlaygroundHomeState`: replace the `ShadTabs` strip + `_demoTabsKey` with the sidebar/drawer shell built from `DemoNavList`; add a `_bodyKey` GlobalKey on the `IndexedStack`; widen the `material` import to add `Scaffold, Drawer`.
- **Modify** `apps/jet_print_playground/test/app_consumes_library_test.dart` — migrate the 6 tests that target `ShadTab<String>` to the new `DemoNavList` model.

---

### Task 1: `DemoNavList` shared navigation widget

**Files:**
- Create: `apps/jet_print_playground/lib/demo_nav_list.dart`
- Test: `apps/jet_print_playground/test/demo_nav_list_test.dart`

**Interfaces:**
- Produces:
  - `class DemoNavItem { const DemoNavItem({required String value, required IconData icon, required String label}); final String value; final IconData icon; final String label; }`
  - `class DemoNavList extends StatelessWidget { const DemoNavList({super.key, required List<DemoNavItem> items, required String selected, required ValueChanged<String> onSelect}); }`
  - Renders one `ShadButton` per item (label as its text `child`, icon as `leading`); the item whose `value == selected` uses `ShadButton.secondary`, the rest `ShadButton.ghost`; tapping an item calls `onSelect(item.value)`.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/demo_nav_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print_playground/demo_nav_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  const List<DemoNavItem> items = <DemoNavItem>[
    DemoNavItem(value: 'a', icon: LucideIcons.fileText, label: 'Alpha'),
    DemoNavItem(value: 'b', icon: LucideIcons.tag, label: 'Bravo'),
    DemoNavItem(value: 'c', icon: LucideIcons.package, label: 'Charlie'),
  ];

  Widget host({
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return ShadApp(
      home: Scaffold(
        body: SizedBox(
          width: 220,
          child: DemoNavList(
            items: items,
            selected: selected,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  testWidgets('renders one labeled tile per item', (WidgetTester tester) async {
    await tester.pumpWidget(host(selected: 'a', onSelect: (_) {}));
    for (final DemoNavItem item in items) {
      expect(find.text(item.label), findsOneWidget, reason: item.label);
    }
  });

  testWidgets('tapping a tile reports that item value',
      (WidgetTester tester) async {
    final List<String> taps = <String>[];
    await tester.pumpWidget(host(selected: 'a', onSelect: taps.add));
    await tester.tap(find.text('Bravo'));
    await tester.pumpAndSettle();
    expect(taps, <String>['b']);
  });

  testWidgets('the selected item uses a distinct (secondary) button',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(selected: 'b', onSelect: (_) {}));
    // The selected entry is the only filled `secondary` button; the rest are
    // ghost. shadcn exposes the variant on ShadButton.variant.
    final Iterable<ShadButton> buttons =
        tester.widgetList<ShadButton>(find.byType(ShadButton));
    final ShadButton selected = buttons.firstWhere(
        (ShadButton b) => b.variant == ShadButtonVariant.secondary);
    expect((selected.child as Text).data, 'Bravo');
    expect(
        buttons.where((ShadButton b) => b.variant == ShadButtonVariant.ghost)
            .length,
        2,
        reason: 'the two unselected entries stay ghost');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/jet_print_playground && flutter test test/demo_nav_list_test.dart`
Expected: FAIL — `demo_nav_list.dart` / `DemoNavList` does not exist (compile error: `Target of URI doesn't exist`).

- [ ] **Step 3: Write the widget**

Create `apps/jet_print_playground/lib/demo_nav_list.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// One entry in the playground's demo navigation: the stable [value] that keys
/// the selected demo, the [icon] shown beside it, and the localized [label].
@immutable
class DemoNavItem {
  const DemoNavItem({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

/// A vertical, scrollable list of selectable demo entries, shared by the wide
/// layout's fixed sidebar and the narrow layout's hamburger drawer.
///
/// Stateless: the parent owns [selected] and is notified through [onSelect].
/// The widget carries no chrome (border/width) — that is the caller's job — so
/// the identical list renders in either host.
class DemoNavList extends StatelessWidget {
  const DemoNavList({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<DemoNavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final DemoNavItem item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: _tile(item),
            ),
        ],
      ),
    );
  }

  // A selected entry uses the filled `secondary` variant for an accent
  // background; the rest are borderless `ghost`. Both are full-width and
  // left-aligned (`mainAxisAlignment: start`) so the icon+label read as a list
  // row, not a centered button.
  Widget _tile(DemoNavItem item) {
    final bool isSelected = item.value == selected;
    final Widget leading = Icon(item.icon, size: 16);
    final Widget label = Text(item.label);
    void onPressed() => onSelect(item.value);
    return isSelected
        ? ShadButton.secondary(
            width: double.infinity,
            mainAxisAlignment: MainAxisAlignment.start,
            leading: leading,
            onPressed: onPressed,
            child: label,
          )
        : ShadButton.ghost(
            width: double.infinity,
            mainAxisAlignment: MainAxisAlignment.start,
            leading: leading,
            onPressed: onPressed,
            child: label,
          );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/jet_print_playground && flutter test test/demo_nav_list_test.dart`
Expected: PASS (3 tests). If the variant test fails because the resolved `shadcn_ui` exposes the field under a different name, run `flutter analyze` and inspect `ShadButton`'s public fields, then adjust the field reference in the test only — the widget code is the source of truth.

- [ ] **Step 5: Commit**

```bash
git add apps/jet_print_playground/lib/demo_nav_list.dart apps/jet_print_playground/test/demo_nav_list_test.dart
git commit -m "feat(playground): add shared DemoNavList selectable nav widget"
```

---

### Task 2: Wire the sidebar + hamburger-drawer shell

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart` (imports ~line 7; `_PlaygroundHomeState` lines ~170–408)

**Interfaces:**
- Consumes: `DemoNavItem`, `DemoNavList` from Task 1.
- Produces: a `_PlaygroundHome` whose `build` returns a `Scaffold` with a nav `Drawer`; the wide branch shows a fixed `DemoNavList` sidebar; the narrow branch shows a hamburger that opens the drawer. `_selectedDemo` and the `IndexedStack` body semantics are unchanged.

- [ ] **Step 1: Add the `DemoNavList` import and widen the material import**

In `apps/jet_print_playground/lib/main.dart`, change the material import line:

```dart
import 'package:flutter/material.dart' show ThemeMode;
```
to:
```dart
import 'package:flutter/material.dart' show ThemeMode, Scaffold, Drawer;
```

And add to the local import block (alongside the other `import '...sample.dart';` lines, kept alphabetical):

```dart
import 'demo_nav_list.dart';
```

- [ ] **Step 2: Replace the `_demoTabsKey` field with `_bodyKey`**

In `_PlaygroundHomeState`, replace this field and its doc comment (lines ~177–180):

```dart
  /// A stable identity for the demo [ShadTabs] so the selector strip survives
  /// the narrow⇄wide layout swap (e.g. a phone rotation crossing [_narrowWidth])
  /// and the parent's theme/locale rebuilds.
  final GlobalKey _demoTabsKey = GlobalKey();
```

with:

```dart
  /// A stable identity for the demo body [IndexedStack] so it survives the
  /// narrow⇄wide layout swap. On that swap the sidebar appears/disappears as a
  /// sibling of the body; without this key the body's element would reparent
  /// and every designer would remount (losing in-progress edits). The GlobalKey
  /// migrates the element intact across the rebuild.
  final GlobalKey _bodyKey = GlobalKey();
```

- [ ] **Step 3: Rewrite `build` (lines ~288–408)**

Replace the entire `build` method body — from `Widget build(BuildContext context) {` through its closing `}` at line ~408 — with:

```dart
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Labels are l10n-dependent so they're resolved per build; the bodies are
    // stable instances from initState.
    final List<String> labels = <String>[
      l10n.tabInvoice,
      l10n.tabLabel,
      l10n.tabBarcode,
      'Symbologies',
      l10n.tabPackingSlip,
      l10n.tabPayroll,
      l10n.tabList,
      l10n.tabLedger,
      l10n.tabMenu,
      'Custom',
      l10n.tabEmpty,
    ];

    // The shared nav model: zip the stable registry with the per-build labels.
    // One source drives both the wide sidebar and the narrow drawer.
    final List<DemoNavItem> navItems = <DemoNavItem>[
      for (int i = 0; i < _demoBodies.length; i++)
        DemoNavItem(
          value: _demoBodies[i].value,
          icon: _demoBodies[i].icon,
          label: labels[i],
        ),
    ];

    final int index = _demoBodies
        .indexWhere((d) => d.value == _selectedDemo)
        .clamp(0, _demoBodies.length - 1);

    // The hero: one structurally-stable IndexedStack keeps every designer
    // mounted (edits survive) and swaps which is shown by index alone. The
    // [_bodyKey] preserves this element across the wide⇄narrow swap.
    final Widget bodies = IndexedStack(
      key: _bodyKey,
      index: index,
      sizing: StackFit.expand,
      children: <Widget>[for (final d in _demoBodies) d.body],
    );

    void select(String value) => setState(() => _selectedDemo = value);

    // App-global theme + language toggles: they switch the WHOLE app, not any
    // single report, so they ride in the top bar, never the per-demo nav.
    final Widget toggleCluster = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: widget.onToggleTheme,
          child: Text(widget.isDark ? 'Light' : 'Dark'),
        ),
        const SizedBox(width: 4),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: widget.onCycleLanguage,
          child: Text(widget.localeCode.toUpperCase()),
        ),
      ],
    );

    // The drawer hosts the same nav on narrow screens; selecting an item closes
    // it. It is always supplied (harmless on wide, where no hamburger opens it)
    // so the Scaffold — and thus [bodies] in its body — stays structurally
    // constant across the layout swap.
    final Widget navDrawer = Drawer(
      child: SafeArea(
        child: DemoNavList(
          items: navItems,
          selected: _selectedDemo,
          onSelect: (String value) {
            select(value);
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    final ShadThemeData theme = ShadTheme.of(context);

    return Scaffold(
      drawer: navDrawer,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < _narrowWidth) {
              // Narrow: a hamburger opens the drawer; toggles sit at the right.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: <Widget>[
                        // A Builder gives a context under the Scaffold so
                        // Scaffold.of finds it to open the drawer.
                        Builder(
                          builder: (BuildContext ctx) => ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                            child: const Icon(LucideIcons.menu, size: 16),
                          ),
                        ),
                        const Spacer(),
                        toggleCluster,
                      ],
                    ),
                  ),
                  Expanded(child: bodies),
                ],
              );
            }
            // Wide: a persistent fixed sidebar owns demo selection; the toggles
            // sit in a slim top bar over the body.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 220,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: theme.colorScheme.border),
                    ),
                  ),
                  child: DemoNavList(
                    items: navItems,
                    selected: _selectedDemo,
                    onSelect: select,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding:
                            const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: toggleCluster,
                        ),
                      ),
                      Expanded(child: bodies),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
```

- [ ] **Step 4: Analyze — confirm no leftover references**

Run: `cd apps/jet_print_playground && flutter analyze`
Expected: No errors. In particular, no "unused" warning for `ShadTabs`/`ShadTab` (they were never imported by name — they came from the `shadcn_ui` barrel) and no reference to the removed `_demoTabsKey`. If analyze reports `_demoTabsKey` still referenced, you missed Step 2.

- [ ] **Step 5: Commit**

```bash
git add apps/jet_print_playground/lib/main.dart
git commit -m "feat(playground): demo left-nav sidebar + hamburger drawer

Replaces the top ShadTabs strip. Wide screens get a persistent fixed
DemoNavList sidebar; narrow screens get a Scaffold drawer opened by a
hamburger. The IndexedStack body keeps a stable GlobalKey so designers
never remount across the wide/narrow swap."
```

---

### Task 3: Migrate the shell consumption tests to the new nav

The shell rewrite breaks `app_consumes_library_test.dart`, which still taps
`ShadTab<String>`. Migrate its 6 affected tests to the `DemoNavList` model.

**Files:**
- Modify: `apps/jet_print_playground/test/app_consumes_library_test.dart`

**Interfaces:**
- Consumes: `DemoNavList` (Task 1), the new shell (Task 2).

- [ ] **Step 1: Run the suite to see the failures (red)**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart`
Expected: FAIL — the `ShadTab<String>` finders match nothing now (`findsOneWidget` failures) and the phone-geometry assertion is stale.

- [ ] **Step 2: Add the import and a nav-entry finder helper**

Add to the import block of `test/app_consumes_library_test.dart`:

```dart
import 'package:jet_print_playground/demo_nav_list.dart';
```

Add this helper at the top of `void main() {`, before the first `testWidgets`:

```dart
  // A nav entry is a ShadButton (label as its text) inside the shared
  // DemoNavList. Scoping to DemoNavList avoids matching the identical report
  // name the designer's own top bar shows. On a wide surface only the sidebar
  // copy is onstage (the drawer copy is offstage), so a default find matches
  // exactly one; on a phone the only copy is the drawer's, onstage once opened.
  Finder navItem(String label) => find.descendant(
        of: find.byType(DemoNavList),
        matching: find.widgetWithText(ShadButton, label),
      );
```

- [ ] **Step 3: Migrate the "eleven live designer tabs" test (lines ~31–63)**

In the test titled `'the shell shows eleven live designer tabs and no placeholder'`, replace the label loop body:

```dart
        expect(find.widgetWithText(ShadTab<String>, label), findsOneWidget,
            reason: '"$label" tab label');
```
with:
```dart
        expect(navItem(label), findsOneWidget, reason: '"$label" nav entry');
```

- [ ] **Step 4: Migrate the "Empty tab activates" test (lines ~65–97)**

Replace:
```dart
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
```
with:
```dart
      await tester.tap(navItem('Empty'));
```

- [ ] **Step 5: Replace the phone-geometry test (lines ~99–142) entirely**

Replace the whole `testWidgets('at phone width every demo tab is reachable, ...')` block with a drawer-reachability test:

```dart
  testWidgets(
    'at phone width the hamburger drawer reaches every demo',
    (WidgetTester tester) async {
      // A phone-portrait surface (below the 600px shell breakpoint).
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the shell lays out cleanly at phone width');

      // The nav lives in a closed drawer — no entry is onstage yet.
      expect(navItem('Invoice'), findsNothing,
          reason: 'nav is hidden until the hamburger is tapped');

      // Open the drawer via the hamburger.
      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pumpAndSettle();

      // Every demo entry is now present and reachable in the open drawer.
      for (final String label in const <String>[
        'Invoice',
        'Label',
        'Barcode',
        'Symbologies',
        'Packing slip',
        'Payroll',
        'List',
        'Ledger',
        'Menu',
        'Custom',
        'Empty',
      ]) {
        expect(navItem(label), findsOneWidget, reason: '"$label" nav entry');
      }

      // Selecting an entry closes the drawer (and switches the demo).
      await tester.tap(navItem('Menu'));
      await tester.pumpAndSettle();
      expect(navItem('Menu'), findsNothing,
          reason: 'the drawer closes after a selection');
    },
  );
```

- [ ] **Step 6: Migrate the remaining three `ShadTab` taps**

In `'only the Empty demo wires the Save/Open callbacks (FR-022)'` (~line 161), `'Open/Save show only on the Empty demo (gated host file I/O)'` (~line 184), and `'a designer survives a tab switch as the SAME State ...'` (~lines 211 & 213), replace every:

```dart
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
```
with:
```dart
      await tester.tap(navItem('Empty'));
```
and the one:
```dart
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Invoice'));
```
with:
```dart
      await tester.tap(navItem('Invoice'));
```

(All three of these tests already set a wide `Size(1850, 700)` surface, so the
sidebar copy is onstage and `navItem` matches it.)

- [ ] **Step 7: Run the migrated test file (green)**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart`
Expected: PASS (all tests). If a wide-surface tap reports "found 2 widgets", the drawer copy became onstage — confirm the surface is ≥600 wide so only the sidebar is onstage.

- [ ] **Step 8: Commit**

```bash
git add apps/jet_print_playground/test/app_consumes_library_test.dart
git commit -m "test(playground): migrate shell tests from ShadTabs to DemoNavList"
```

---

### Task 4: Full verification + GUI walk

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole package**

Run: `cd apps/jet_print_playground && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: Run the full playground test suite**

Run: `cd apps/jet_print_playground && flutter test`
Expected: All tests pass. The `rendered_*`/definition goldens are unaffected (they render report definitions, not the shell), so no golden regeneration is expected. If any `rendered_*` golden fails, STOP — that means the shell change leaked into report output, which it must not.

- [ ] **Step 3: GUI walk (manual)**

Run: `cd apps/jet_print_playground && flutter run -d macos` (or `-d chrome`).
Confirm:
- Wide window: left sidebar lists all 11 demos; the selected one is highlighted; clicking switches the body; theme/language toggles sit top-right.
- Narrow window (resize < 600 wide, or `-d chrome` then narrow the window): the sidebar is gone; a hamburger appears top-left; clicking it slides the drawer in; selecting a demo closes the drawer and switches the body; toggles remain top-right.
- Switch demos, edit something in a designer, switch away and back — the edit survives (no remount).

- [ ] **Step 4: Commit (only if Step 3 surfaced a fix)**

If the GUI walk required a code change, commit it:
```bash
git add -A
git commit -m "fix(playground): <what the GUI walk surfaced>"
```
Otherwise nothing to commit — the feature is complete.

---

## Self-Review

**Spec coverage:**
- Persistent fixed sidebar (wide) → Task 2 Step 3 wide branch. ✓
- Hamburger `Scaffold` drawer (narrow) → Task 2 Step 3 narrow branch + `navDrawer`. ✓
- Shared nav model, one source → `navItems` zip + `DemoNavList` reused in both. ✓
- Top bar = theme+language toggles only → `toggleCluster` in both branches; demo selection moved to nav. ✓
- `IndexedStack` edit-survival preserved → unchanged construction + `_bodyKey`. ✓
- `ShadTabs`/`_demoTabsKey` removed → Task 2 Steps 2–3. ✓
- Drawer closes on selection → `navDrawer.onSelect` calls `Navigator.of(context).pop()`. ✓
- Test impact (smoke test nav selection; no shell goldens) → Task 1 widget test + Task 3 migration; Task 4 Step 2 confirms report goldens untouched. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `DemoNavItem`/`DemoNavList` signatures defined in Task 1 are used verbatim in Task 2/3. `_bodyKey` (defined Task 2 Step 2) used Task 2 Step 3. `navItem` helper (Task 3 Step 2) used in Steps 3–6. `ShadButtonVariant.secondary`/`.ghost` referenced only in the Task 1 variant test, with a Step 4 fallback if the resolved API differs. ✓
