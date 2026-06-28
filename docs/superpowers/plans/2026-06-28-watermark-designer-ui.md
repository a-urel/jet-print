# Watermark Designer UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Watermark** section to the designer's report-root Properties panel so an author can enable and edit a **text** watermark (text, color, font size, opacity, angle) on a report, with live WYSIWYG preview and undo/redo.

**Architecture:** Designer-only. A new undoable `SetWatermarkCommand` + `JetReportDesignerController.setWatermark(Watermark?)` mutate `definition.furniture.watermark`; a new `_watermarkSection()` in the Properties panel (shown when `selection.isReport`) reads and edits it through that controller method. No domain/render/serialization change — the already-shipped engine renders the watermark the moment the definition changes.

**Tech Stack:** Dart / Flutter, `flutter_test` (widget tests), `shadcn_ui` (ShadSwitch/ShadSelect), Flutter `gen-l10n` (ARB localization).

## Global Constraints

- Run `flutter`/`dart` from `packages/jet_print`; run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package — cd back before git). Branch is already `043-watermark-support`.
- **Text watermark only in the UI.** Image watermarks remain API/JSON-authored. An image watermark loaded from JSON must be preserved (never silently dropped by a text edit).
- **Toggle-on default MUST seed a large font:** `Watermark(text: l10n.watermarkDefaultText, textStyle: const JetTextStyle(fontSize: 64))`. `JetTextStyle.fallback` is 12pt and the engine draws text at literal size (no page-scaling), so a 12pt watermark on A4 is a near-invisible dot.
- **Each edit is ONE undoable step** — commit a whole new `Watermark` via `controller.setWatermark(wm.copyWith(...))` (mirrors how text-style edits commit a whole `copyWith`).
- **`PageFurniture.copyWith` cannot null-out `watermark`** (set-only by design). To CLEAR (toggle off), construct a fresh `PageFurniture` with all 6 slots explicit.
- **No domain/render/serialization change.** Uses the shipped `Watermark`, `PageFurniture.watermark`, and codec.
- New l10n keys go in **all three** ARBs (`jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`) then regenerate — never edit only the generated Dart (the chart feature hit ARB/generated drift).
- Dartdoc on the new command + controller method; `dart format` + clean `flutter analyze`.

## Reference: exact widget/API signatures (verified in-tree)

Use these verbatim — do not guess.

- Panel key prefix: `const String _p = 'jet_print.designer.properties';` (already in properties_panel.dart). Field keys are `ValueKey<String>('$_p.field.<name>')`.
- `EditCommand` (base, `designer/controller/edit_command.dart`): `abstract class EditCommand { const EditCommand(); String get label; DesignerDocument apply(DesignerDocument before); }`.
- `DesignerDocument.withDefinition(ReportDefinition definition, ...)` — returns a new document with the swapped definition (the 2nd arg is optional; omit it).
- `JetReportDesignerController._commit(EditCommand)` → bool; it already no-ops when `after.definition == before.definition && after.selection == before.selection`, pushes history, and `notifyListeners()`.
- `_TextInput({required ValueKey<String> fieldKey, required String value, required String placeholder, required ValueChanged<String> onCommit, ...})`.
- `_NumberField({required ValueKey<String> fieldKey, required IconData prefix, required double value, required ValueChanged<double> onCommit, FocusNode? focusNode})`.
- `_ColorField({required String keyBase, required JetColor? value, required ValueChanged<JetColor?> onCommit, bool allowNone = false, bool compact = false, IconData? leadingIcon, String? semanticLabel})` (in `style_editors.dart`). NOTE: `keyBase` is a **String** (not a ValueKey), `onCommit` is `ValueChanged<JetColor?>`.
- `ShadSwitch({Key? key, required bool value, required ValueChanged<bool> onChanged, Widget? label})`.
- `SectionLabel(String text)` (from `designer/layout/region_chrome.dart`) — uppercase section header.
- l10n: access via `JetPrintLocalizations l10n` already threaded into the inspector methods; reference `l10n.<key>`. Regenerate with `flutter gen-l10n` (config: `packages/jet_print/l10n.yaml`, output class `JetPrintLocalizations`).
- `controller.definition.furniture.watermark` is the live `Watermark?`. `Watermark` (from `package:jet_print/jet_print.dart` or `src/domain/watermark.dart`) has `text`, `textStyle`, `imageBytes`, `imageFit`, `opacity`, `angleDegrees`, and `copyWith({text, textStyle, imageBytes, imageFit, opacity, angleDegrees})`.

---

## File Map

- **Create** `packages/jet_print/lib/src/designer/controller/commands/set_watermark_command.dart` — `SetWatermarkCommand` (Task 1).
- **Modify** `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` — add `setWatermark(Watermark?)` (Task 1).
- **Modify** the 3 ARB files + regenerate (Task 2).
- **Modify** `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` — `_watermarkSection()` + call it in `_reportInspector()` (Task 3).
- **Test** `packages/jet_print/test/designer/controller/set_watermark_command_test.dart` (Task 1), `packages/jet_print/test/designer/watermark_properties_test.dart` (Task 3).

---

## Task 1: `SetWatermarkCommand` + `controller.setWatermark`

**Files:**
- Create: `packages/jet_print/lib/src/designer/controller/commands/set_watermark_command.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`
- Test: `packages/jet_print/test/designer/controller/set_watermark_command_test.dart`

**Interfaces:**
- Consumes: `Watermark`, `PageFurniture`, `ReportDefinition.copyWith`, `EditCommand`, `DesignerDocument.withDefinition`.
- Produces: `class SetWatermarkCommand extends EditCommand` (ctor `SetWatermarkCommand(Watermark? watermark)`); `void JetReportDesignerController.setWatermark(Watermark? watermark)`.

- [ ] **Step 1: Write the failing test.**

```dart
// packages/jet_print/test/designer/controller/set_watermark_command_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/controller/commands/set_watermark_command.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/watermark.dart';

ReportDefinition _def({Watermark? watermark}) => ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(watermark: watermark),
      body: const ReportBody(root: DetailScope()),
    );

void main() {
  group('SetWatermarkCommand', () {
    test('sets a watermark onto furniture', () {
      final DesignerDocument before = DesignerDocument(definition: _def());
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'DRAFT')).apply(before);
      expect(after.definition.furniture.watermark,
          const Watermark(text: 'DRAFT'));
    });

    test('clears the watermark (null) — copyWith cannot, so fresh furniture', () {
      final DesignerDocument before =
          DesignerDocument(definition: _def(watermark: const Watermark(text: 'X')));
      final DesignerDocument after =
          const SetWatermarkCommand(null).apply(before);
      expect(after.definition.furniture.watermark, isNull);
    });

    test('preserves other furniture slots when setting watermark', () {
      const header = Band(id: 'ph', type: BandType.pageHeader, height: 20);
      final DesignerDocument before = DesignerDocument(
          definition: ReportDefinition(
              name: 'r',
              page: PageFormat.a4Portrait,
              furniture: const PageFurniture(pageHeader: header),
              body: const ReportBody(root: DetailScope())));
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'D')).apply(before);
      expect(after.definition.furniture.pageHeader, header);
      expect(after.definition.furniture.watermark, const Watermark(text: 'D'));
    });

    test('no-op when watermark already equals target', () {
      final DesignerDocument before =
          DesignerDocument(definition: _def(watermark: const Watermark(text: 'D')));
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'D')).apply(before);
      expect(identical(after, before), isTrue);
    });
  });
}
```

> VERIFY before running: the exact `DesignerDocument` constructor (it may be `DesignerDocument(definition: ...)` or a factory — read `designer/controller/designer_document.dart`), the `ReportBody`/`DetailScope`/`Band`/`BandType` import paths, and `PageFormat.a4Portrait`. Adapt the fixture construction to the real constructors; keep the four assertions.

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/designer/controller/set_watermark_command_test.dart`
Expected: FAIL — `set_watermark_command.dart` does not exist.

- [ ] **Step 3: Implement the command.**

```dart
// packages/jet_print/lib/src/designer/controller/commands/set_watermark_command.dart
/// The command that sets (or clears) the report's page watermark.
library;

import '../../../domain/report_definition.dart';
import '../../../domain/watermark.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets `furniture.watermark` to [watermark] (null clears it).
///
/// [PageFurniture.copyWith] is set-only and cannot null a slot, so [apply]
/// constructs a fresh [PageFurniture] with every existing slot copied and
/// `watermark` set explicitly — the only way to support clearing. Returns the
/// document unchanged when the watermark already equals [watermark] (no-op);
/// the selection is untouched, so undo restores the exact prior watermark.
class SetWatermarkCommand extends EditCommand {
  /// Creates a watermark change to [watermark] (null clears).
  const SetWatermarkCommand(this.watermark);

  /// The new watermark, or null to remove it.
  final Watermark? watermark;

  @override
  String get label => 'Set watermark';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final PageFurniture f = before.definition.furniture;
    if (f.watermark == watermark) return before;
    final PageFurniture next = PageFurniture(
      pageHeader: f.pageHeader,
      pageFooter: f.pageFooter,
      columnHeader: f.columnHeader,
      columnFooter: f.columnFooter,
      background: f.background,
      watermark: watermark,
    );
    return before.withDefinition(before.definition.copyWith(furniture: next));
  }
}
```

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/designer/controller/set_watermark_command_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Add the controller method.** In `jet_report_designer_controller.dart`, near `setPageFormat` (~line 692), add (and add the `Watermark`/command imports at the top — mirror the existing command import style):

```dart
  /// Sets (or clears, with null) the report's page watermark as one undoable
  /// step. Routed through `_commit`, so setting the current watermark records no
  /// history; canvas/preview/export all read `definition.furniture.watermark`,
  /// so the one notification propagates everywhere (WYSIWYG).
  void setWatermark(Watermark? watermark) =>
      _commit(SetWatermarkCommand(watermark));
```

Add a controller-level test (extend an existing controller test file, or add to the command test file a `TestWidgetsFlutterBinding`-free group) proving the round trip + undo:

```dart
// add to set_watermark_command_test.dart (or the controller's test file)
test('controller.setWatermark commits and is undoable', () {
  final c = JetReportDesignerController(definition: _def());
  c.setWatermark(const Watermark(text: 'DRAFT'));
  expect(c.definition.furniture.watermark, const Watermark(text: 'DRAFT'));
  expect(c.canUndo, isTrue);
  c.undo();
  expect(c.definition.furniture.watermark, isNull);
});
```

> VERIFY the `JetReportDesignerController` constructor shape (it may take `definition:` or a `DesignerDocument`) and `canUndo`/`undo()` names by reading the controller. Import it in the test.

- [ ] **Step 6: Run both tests → PASS.**

Run: `cd packages/jet_print && flutter test test/designer/controller/set_watermark_command_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 7: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/designer/controller/commands/set_watermark_command.dart lib/src/designer/controller/jet_report_designer_controller.dart test/designer/controller/set_watermark_command_test.dart && flutter analyze lib/src/designer/controller
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/ packages/jet_print/test/designer/controller/set_watermark_command_test.dart
git commit -m "feat(designer): SetWatermarkCommand + controller.setWatermark (undoable)"
```

---

## Task 2: Localization keys

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`
- Regenerate: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations*.dart` (via `flutter gen-l10n`)

**Interfaces:**
- Produces: `l10n.propertiesWatermark`, `.watermarkEnable`, `.watermarkText`, `.watermarkColor`, `.watermarkFontSize`, `.watermarkOpacity`, `.watermarkAngle`, `.watermarkDefaultText`, `.watermarkImageExternal` on `JetPrintLocalizations`.

- [ ] **Step 1: Add the keys to `jet_print_en.arb`.** Insert near the other `properties*` keys (after `propertiesMargins`, ~line 506). Each key needs an `@`-description.

```json
  "propertiesWatermark": "Watermark",
  "@propertiesWatermark": { "description": "Properties panel section label for the report watermark." },
  "watermarkEnable": "Enable",
  "@watermarkEnable": { "description": "Toggle that turns the report watermark on or off." },
  "watermarkText": "Text",
  "@watermarkText": { "description": "Label for the watermark's text content." },
  "watermarkColor": "Color",
  "@watermarkColor": { "description": "Label for the watermark text color picker." },
  "watermarkFontSize": "Font size",
  "@watermarkFontSize": { "description": "Label for the watermark text font size field." },
  "watermarkOpacity": "Opacity",
  "@watermarkOpacity": { "description": "Label for the watermark opacity field (0 to 1)." },
  "watermarkAngle": "Angle",
  "@watermarkAngle": { "description": "Label for the watermark rotation angle field, in degrees." },
  "watermarkDefaultText": "DRAFT",
  "@watermarkDefaultText": { "description": "Default text inserted when a watermark is first enabled." },
  "watermarkImageExternal": "Image watermark (set outside the designer)",
  "@watermarkImageExternal": { "description": "Read-only note shown when the report has an image watermark, which the designer cannot edit." },
```

- [ ] **Step 2: Add the SAME keys to `jet_print_de.arb` and `jet_print_tr.arb`** with translated values (descriptions optional in non-template ARBs but keep the keys). Suggested:
  - de: `propertiesWatermark`="Wasserzeichen", `watermarkEnable`="Aktivieren", `watermarkText`="Text", `watermarkColor`="Farbe", `watermarkFontSize`="Schriftgröße", `watermarkOpacity`="Deckkraft", `watermarkAngle`="Winkel", `watermarkDefaultText`="ENTWURF", `watermarkImageExternal`="Bild-Wasserzeichen (außerhalb des Designers gesetzt)".
  - tr: `propertiesWatermark`="Filigran", `watermarkEnable`="Etkinleştir", `watermarkText`="Metin", `watermarkColor`="Renk", `watermarkFontSize`="Yazı boyutu", `watermarkOpacity`="Opaklık", `watermarkAngle`="Açı", `watermarkDefaultText`="TASLAK", `watermarkImageExternal`="Görsel filigran (tasarımcı dışında ayarlandı)".

> Match each file's existing JSON shape (the non-template ARBs may omit `@`-descriptions — follow what's already there). Keep valid JSON (commas!).

- [ ] **Step 3: Regenerate localizations.**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: regenerates `jet_print_localizations*.dart` with the 9 new getters, no errors.

- [ ] **Step 4: Verify the keys exist in generated Dart and all 3 ARBs.**

Run: `cd packages/jet_print && grep -l "watermarkDefaultText" lib/src/designer/l10n/jet_print_*.arb && grep "watermarkDefaultText" lib/src/designer/l10n/jet_print_localizations.dart`
Expected: all 3 ARB files listed, and the getter present in the generated base class. Then `flutter analyze lib/src/designer/l10n` → clean.

- [ ] **Step 5: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n/
git commit -m "feat(designer,l10n): watermark properties strings (en/de/tr)"
```

---

## Task 3: `_watermarkSection()` in the report-root inspector

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`
- Test: `packages/jet_print/test/designer/watermark_properties_test.dart`

**Interfaces:**
- Consumes: `controller.setWatermark` (Task 1), the l10n keys (Task 2), `Watermark`, `_TextInput`/`_NumberField`/`_ColorField`/`ShadSwitch`/`SectionLabel`.
- Produces: the Watermark UI in the report-root inspector.

- [ ] **Step 1: Write the failing widget tests.**

```dart
// packages/jet_print/test/designer/watermark_properties_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/controller/jet_report_designer_controller.dart';
import 'package:jet_print/src/domain/watermark.dart';
// Reuse the harness helpers from properties_editor_test.dart by importing/copying
// pumpDesignerWith + _field + _editable. Read that file first and mirror it.

void main() {
  // _p prefix used by field keys:
  const String p = 'jet_print.designer.properties';
  Finder field(String name) => find.byKey(ValueKey<String>('$p.field.$name'));
  Finder editable(String name) =>
      find.descendant(of: field(name), matching: find.byType(EditableText));

  testWidgets('report root shows the watermark toggle; enabling sets a default',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    expect(field('watermarkEnable'), findsOneWidget);
    expect(c.definition.furniture.watermark, isNull);

    await tester.tap(field('watermarkEnable'));
    await tester.pumpAndSettle();

    final Watermark? wm = c.definition.furniture.watermark;
    expect(wm, isNotNull);
    expect(wm!.text, isNotEmpty);
    expect(wm.textStyle.fontSize, 64); // large default, not 12
  });

  testWidgets('editing the watermark text commits as one undoable step',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(const Watermark(text: 'DRAFT', textStyle: JetTextStyle(fontSize: 64)));
    c.selectReport();
    await tester.pumpAndSettle();

    await tester.enterText(editable('watermarkText'), 'CONFIDENTIAL');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(c.definition.furniture.watermark?.text, 'CONFIDENTIAL');
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.definition.furniture.watermark?.text, 'DRAFT');
  });

  testWidgets('editing opacity commits to the model',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(const Watermark(text: 'D', textStyle: JetTextStyle(fontSize: 64)));
    c.selectReport();
    await tester.pumpAndSettle();

    await tester.enterText(editable('watermarkOpacity'), '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.furniture.watermark?.opacity, 0.5);
  });

  testWidgets('disabling clears the watermark', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(const Watermark(text: 'D', textStyle: JetTextStyle(fontSize: 64)));
    c.selectReport();
    await tester.pumpAndSettle();

    await tester.tap(field('watermarkEnable'));
    await tester.pumpAndSettle();
    expect(c.definition.furniture.watermark, isNull);
  });

  testWidgets('an image watermark shows the read-only note, text field hidden, '
      'and an opacity edit preserves the image bytes',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 3]), opacity: 0.3));
    c.selectReport();
    await tester.pumpAndSettle();

    expect(field('watermarkText'), findsNothing);
    await tester.enterText(editable('watermarkOpacity'), '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.furniture.watermark?.imageBytes, isNotNull);
    expect(c.definition.furniture.watermark?.opacity, 0.5);
  });
}
```

> READ `test/designer/properties_editor_test.dart` first and reuse its real `pumpDesignerWith` / `_openProperties` / key helpers (import or copy them). Add `import 'dart:typed_data';` for `Uint8List`. If `pumpDesignerWith` already opens the Properties tab, drop any extra open call; if a separate `_openProperties(tester)` is needed before `selectReport`, include it. Keep the five behavioral assertions.

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/designer/watermark_properties_test.dart`
Expected: FAIL — `watermarkEnable` field not found (section not built yet).

- [ ] **Step 3: Implement `_watermarkSection()`** in `_PropertiesPanelState` (place it near the other inspector helpers). Add `import` for `Watermark` (via `package:jet_print/src/domain/watermark.dart`) and ensure `JetTextStyle`/`JetColor`/`LucideIcons` are already imported (they are — used elsewhere in the file).

```dart
  /// The report-level watermark editors (text watermark authoring). Shown in the
  /// report-root inspector. The enable toggle creates a large-font default so the
  /// watermark is visible immediately; an image watermark (no UI to author bytes)
  /// is shown read-only with opacity/angle still editable.
  List<Widget> _watermarkSection(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final Watermark? wm = controller.definition.furniture.watermark;
    final List<Widget> out = <Widget>[
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesWatermark),
      ShadSwitch(
        key: const ValueKey<String>('$_p.field.watermarkEnable'),
        value: wm != null,
        onChanged: (bool on) => controller.setWatermark(on
            ? Watermark(
                text: l10n.watermarkDefaultText,
                textStyle: const JetTextStyle(fontSize: 64))
            : null),
        label: Text(l10n.watermarkEnable),
      ),
    ];
    if (wm == null) return out;

    final bool isImage = wm.imageBytes != null && wm.text == null;
    if (isImage) {
      out
        ..add(const SizedBox(height: 10))
        ..add(Text(l10n.watermarkImageExternal, style: theme.textTheme.muted))
        ..add(const SizedBox(height: 10))
        ..add(_watermarkOpacity(controller, wm, l10n))
        ..add(const SizedBox(height: 8))
        ..add(_watermarkAngle(controller, wm, l10n));
      return out;
    }

    out
      ..add(const SizedBox(height: 10))
      ..add(SectionLabel(l10n.watermarkText))
      ..add(_TextInput(
        fieldKey: const ValueKey<String>('$_p.field.watermarkText'),
        value: wm.text ?? '',
        placeholder: l10n.watermarkDefaultText,
        onCommit: (String v) => controller.setWatermark(wm.copyWith(text: v)),
      ))
      ..add(const SizedBox(height: 8))
      ..add(SectionLabel(l10n.watermarkColor))
      ..add(_ColorField(
        keyBase: '$_p.field.watermarkColor',
        value: wm.textStyle.color,
        onCommit: (JetColor? c) => controller.setWatermark(wm.copyWith(
            textStyle: wm.textStyle.copyWith(color: c ?? JetColor.black))),
      ))
      ..add(const SizedBox(height: 8))
      ..add(_NumberField(
        fieldKey: const ValueKey<String>('$_p.field.watermarkFontSize'),
        prefix: LucideIcons.type,
        value: wm.textStyle.fontSize,
        onCommit: (double v) => controller.setWatermark(
            wm.copyWith(textStyle: wm.textStyle.copyWith(fontSize: v))),
      ))
      ..add(const SizedBox(height: 8))
      ..add(_watermarkOpacity(controller, wm, l10n))
      ..add(const SizedBox(height: 8))
      ..add(_watermarkAngle(controller, wm, l10n));
    return out;
  }

  Widget _watermarkOpacity(
          JetReportDesignerController controller, Watermark wm,
          JetPrintLocalizations l10n) =>
      _NumberField(
        fieldKey: const ValueKey<String>('$_p.field.watermarkOpacity'),
        prefix: LucideIcons.droplet,
        value: wm.opacity,
        onCommit: (double v) => controller.setWatermark(wm.copyWith(opacity: v)),
      );

  Widget _watermarkAngle(
          JetReportDesignerController controller, Watermark wm,
          JetPrintLocalizations l10n) =>
      _NumberField(
        fieldKey: const ValueKey<String>('$_p.field.watermarkAngle'),
        prefix: LucideIcons.rotateCw,
        value: wm.angleDegrees,
        onCommit: (double v) =>
            controller.setWatermark(wm.copyWith(angleDegrees: v)),
      );
```

> VERIFY: the `LucideIcons.*` names exist (the file already uses LucideIcons — pick any valid existing icons if `type`/`droplet`/`rotateCw` aren't present; the icon is cosmetic). Confirm `ShadThemeData.textTheme.muted` is the right muted text style (grep the file for an existing muted `Text` usage and mirror it). Confirm `_ColorField` is in scope in this file (it's a `part`/private of the panel per the map).

- [ ] **Step 4: Call `_watermarkSection()` from `_reportInspector()`.** In `_reportInspector` (~line 1438), just before the closing `];` of the returned list (after the margins `Row`), spread the section in:

```dart
      // ... existing margins Row is the last entry ...
      ..._watermarkSection(controller, theme, l10n),
    ];
```

(`_reportInspector` already has `controller`, `theme`, `l10n` in scope.)

- [ ] **Step 5: Run the widget tests → PASS.**

Run: `cd packages/jet_print && flutter test test/designer/watermark_properties_test.dart`
Expected: PASS (5 tests). If `enterText` on opacity rejects `0.5`, confirm `_NumberField` accepts decimals (it parses doubles); if it strips to int, adjust the field or test per the real `_NumberField` parsing.

- [ ] **Step 6: Run the full designer suite (regression).**

Run: `cd packages/jet_print && flutter test test/designer`
Expected: PASS — the new section only renders for `selection.isReport`; existing inspectors unchanged. No golden should change (Properties panel isn't a canvas golden). If a designer golden changes, STOP and inspect.

- [ ] **Step 7: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/designer/layout/panels/properties_panel.dart test/designer/watermark_properties_test.dart && flutter analyze lib/src/designer/layout/panels/properties_panel.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/watermark_properties_test.dart
git commit -m "feat(designer): watermark authoring section in report-root Properties"
```

---

## Task 4: Verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Package analyze + format.**

```bash
cd packages/jet_print
flutter analyze            # clean (only pre-existing infos, if any — none NEW)
dart format --output=none --set-exit-if-changed lib test   # clean
```

- [ ] **Step 2: Full package test.**

Run: `cd packages/jet_print && flutter test`
Expected: all green. **No pre-existing golden changes** (this is author-time-only UI). If any golden fails, STOP and inspect.

- [ ] **Step 3: Playground builds (the library consumer).**

Run: `cd apps/jet_print_playground && flutter analyze && flutter test`
Expected: green.

- [ ] **Step 4: Manual GUI smoke (optional but recommended).**

`cd apps/jet_print_playground && flutter run -d macos` → open a report → select the report root → the **Watermark** section appears → toggle on → a large "DRAFT" appears diagonally on the canvas/draft preview → edit text/opacity/angle and watch it update live → undo reverts. Confirm and note the result.

- [ ] **Step 5: Commit** (only if Step 4 produced any test-only tweak; otherwise nothing to commit).

---

## Self-Review

- **Spec coverage:** `SetWatermarkCommand` + `setWatermark` → Task 1 (incl. fresh-`PageFurniture` clear path + no-op + slot preservation). l10n in all 3 locales → Task 2. `_watermarkSection` enable toggle + text/color/size/opacity/angle editors, default `fontSize: 64`, image read-only edge, append in `_reportInspector` → Task 3. WYSIWYG/undo are inherent in the command pipeline (Task 1) + verified live in Task 4 Step 4. Tests (command, controller, widget) → Tasks 1 & 3. Sweep + playground → Task 4.
- **Placeholder scan:** the "READ/VERIFY" notes name the exact file to mirror and the concrete assertions to keep; every code-bearing step shows full code. No TBD/TODO.
- **Type consistency:** `setWatermark(Watermark?)` defined Task 1, consumed Task 3. `SetWatermarkCommand(Watermark?)` consistent. Field keys (`watermarkEnable`/`watermarkText`/`watermarkColor`/`watermarkFontSize`/`watermarkOpacity`/`watermarkAngle`) match between the panel code (Task 3 Step 3) and the tests (Task 3 Step 1). l10n getter names match between Task 2 and Task 3.
- **Key risks:** (1) `_NumberField` decimal parsing for opacity — flagged in Task 3 Step 5. (2) `wm` null-promotion — handled by early `return out` after the `wm == null` check so `wm` is non-null in the editor block. (3) `PageFurniture.copyWith` can't clear — handled by fresh construction (Task 1). (4) l10n ARB/generated drift — Task 2 Step 4 verifies all 3 ARBs + generated.
