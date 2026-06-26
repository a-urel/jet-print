# Select Data Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the designer has no attached data source, the Data Source panel offers a "Select data source" button that loads a `*.jetreport.datasource` file (schema + optional sample) and attaches it — wired end-to-end in the playground's Empty demo.

**Architecture:** A new pure, public, versioned codec (`JetDataSourceFile`) reads/writes the `*.jetreport.datasource` JSON document (a `FieldDef`-tree schema plus optional sample rows). A new guarded host callback (`onSelectDataSchema`) flows from `JetReportWorkspace` → `JetReportDesigner` → `DesignerSchemaScope` to the Data Source panel, which shows the button only when the callback is wired and no schema is attached. The library performs no file I/O; the playground host owns the picker, decodes the file, and updates its own schema state, which flows back through the existing immutable `dataSchema` param.

**Tech Stack:** Dart / Flutter, `flutter_test`, `shadcn_ui` (`ShadButton`), `file_selector`/`cross_file` (playground host I/O only).

## Global Constraints

- Run `flutter`/`dart` from `packages/jet_print` (lib) or `apps/jet_print_playground` (playground). Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package).
- Library does **no filesystem I/O** — all file access is host-side (Constitution II + FR-022).
- Pure data-seam files import no Flutter (`data/serialization/*` may import only `dart:convert` + `data/`/`domain/`).
- TDD: every code step is Red→Green. Commit per task.
- No render-path / golden change. Widget tests only; gate to avoid canvas-golden drift (no `golden` tag).
- Field names are NOT translated; only UI chrome strings are localized.
- File extension is `*.jetreport.datasource`; codec version constant starts at `1`.

---

## File Structure

**Create:**
- `packages/jet_print/lib/src/data/serialization/data_source_format_exception.dart` — `JetDataSourceFormatException`.
- `packages/jet_print/lib/src/data/serialization/data_source_file.dart` — `JetDataSourceDocument` (value type) + `JetDataSourceFile` (codec).
- `packages/jet_print/test/data/serialization/data_source_file_test.dart` — codec tests.
- `packages/jet_print/test/designer/select_data_source_test.dart` — callback + panel widget tests.
- `apps/jet_print_playground/sample_data/invoice.jetreport.datasource` — sample file to pick.

**Modify:**
- `packages/jet_print/lib/jet_print.dart` — export codec, document type, exception, callback typedef.
- `packages/jet_print/lib/src/designer/jet_report_designer.dart` — `ReportSelectDataSourceCallback` typedef + `onSelectDataSchema` field + guarded wiring into `DesignerSchemaScope`.
- `packages/jet_print/lib/src/designer/jet_report_workspace.dart` — `onSelectDataSchema` field + forward.
- `packages/jet_print/lib/src/designer/designer_schema_scope.dart` — carry `onSelectDataSource` callback + `selectCallbackOf` accessor.
- `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` — empty-state button.
- `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` (+ `_en.dart`, `_de.dart`, `_tr.dart`, `jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`) — `dataSourceSelect` string.
- `apps/jet_print_playground/lib/main.dart` — Empty demo: nullable schema state + select-data-source picker.

---

## Task 1: `JetDataSourceFile` codec (pure, public)

**Files:**
- Create: `packages/jet_print/lib/src/data/serialization/data_source_format_exception.dart`
- Create: `packages/jet_print/lib/src/data/serialization/data_source_file.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Test: `packages/jet_print/test/data/serialization/data_source_file_test.dart`

**Interfaces:**
- Consumes: `JetDataSchema` (`data/data_schema.dart`), `FieldDef` + `JetFieldType` (`data/field_def.dart`).
- Produces:
  - `class JetDataSourceFormatException implements Exception { const JetDataSourceFormatException(String message); final String message; }`
  - `class JetDataSourceDocument { const JetDataSourceDocument({required JetDataSchema schema, List<Map<String, Object?>>? sample}); final JetDataSchema schema; final List<Map<String, Object?>>? sample; }`
  - `abstract final class JetDataSourceFile` with `static const int version = 1;` and statics: `Map<String, Object?> encode(JetDataSourceDocument)`, `JetDataSourceDocument decode(Map<String, Object?>)`, `String encodeJson(JetDataSourceDocument)`, `JetDataSourceDocument decodeJson(String)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/serialization/data_source_file_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  group('JetDataSourceFile', () {
    const JetDataSchema schema = JetDataSchema(
      name: 'Invoice',
      fields: <FieldDef>[
        FieldDef('id', type: JetFieldType.integer),
        FieldDef('customer', type: JetFieldType.string),
        FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('sku', type: JetFieldType.string),
          FieldDef('qty', type: JetFieldType.integer),
        ]),
      ],
    );

    test('round-trips schema only (no sample)', () {
      const JetDataSourceDocument doc = JetDataSourceDocument(schema: schema);
      final JetDataSourceDocument back =
          JetDataSourceFile.decodeJson(JetDataSourceFile.encodeJson(doc));
      expect(back.schema, schema);
      expect(back.sample, isNull);
    });

    test('round-trips nested collection fidelity + sample rows', () {
      const JetDataSourceDocument doc = JetDataSourceDocument(
        schema: schema,
        sample: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'customer': 'Acme',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'sku': 'A', 'qty': 2},
            ],
          },
        ],
      );
      final JetDataSourceDocument back =
          JetDataSourceFile.decodeJson(JetDataSourceFile.encodeJson(doc));
      expect(back.schema, schema);
      expect(back.sample, doc.sample);
    });

    test('stamps the version constant', () {
      final Map<String, Object?> json = JetDataSourceFile.encode(
          const JetDataSourceDocument(schema: schema));
      expect(json['jetDataSource'], JetDataSourceFile.version);
    });

    test('rejects a missing/wrong version', () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'schema': <String, Object?>{'name': 'X', 'fields': <Object?>[]},
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('rejects an unknown field type', () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'jetDataSource': 1,
          'schema': <String, Object?>{
            'name': 'X',
            'fields': <Object?>[
              <String, Object?>{'name': 'a', 'type': 'wat'},
            ],
          },
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('rejects non-object JSON text', () {
      expect(() => JetDataSourceFile.decodeJson('[]'),
          throwsA(isA<JetDataSourceFormatException>()));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/serialization/data_source_file_test.dart`
Expected: FAIL — `JetDataSourceFile`/`JetDataSourceDocument` undefined.

- [ ] **Step 3: Create the exception**

Create `packages/jet_print/lib/src/data/serialization/data_source_format_exception.dart`:

```dart
/// Thrown when a `*.jetreport.datasource` document is structurally invalid.
library;

/// A structural fault while decoding a data-source file — a missing/too-new
/// `jetDataSource` version, a malformed shape, or an unknown field type. A
/// fail-fast condition: the document cannot be interpreted at all. Parallel to
/// `ReportFormatException` for the report-definition format.
class JetDataSourceFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const JetDataSourceFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'JetDataSourceFormatException: $message';
}
```

- [ ] **Step 4: Create the codec**

Create `packages/jet_print/lib/src/data/serialization/data_source_file.dart`:

```dart
/// The public, versioned file-format facade for the designer's data source —
/// a `JetDataSchema` plus optional sample rows (`*.jetreport.datasource`).
library;

import 'dart:convert';

import '../data_schema.dart';
import '../field_def.dart';
import 'data_source_format_exception.dart';

/// A decoded `*.jetreport.datasource` document: the data [schema] the designer
/// binds against, plus optional [sample] rows a host may use for preview
/// (null when the file omits them). Value-equality for round-trip testing.
class JetDataSourceDocument {
  /// Creates a document over [schema] with optional [sample] rows.
  const JetDataSourceDocument({required this.schema, this.sample});

  /// The data-source structure the designer displays and binds against.
  final JetDataSchema schema;

  /// Optional sample rows (plain JSON values), or null when absent.
  final List<Map<String, Object?>>? sample;

  @override
  bool operator ==(Object other) =>
      other is JetDataSourceDocument &&
      other.schema == schema &&
      _sampleEquals(other.sample, sample);

  @override
  int get hashCode => Object.hash(schema, _sampleHash(sample));
}

/// Encodes and decodes a [JetDataSourceDocument] to/from the library's
/// versioned JSON format (Constitution V). The library performs no filesystem
/// I/O: a host reads the text and [decodeJson]s it, or [encodeJson]s a document
/// and writes it. The round-trip is lossless over the schema (including nested
/// collection fields); sample rows pass through as plain JSON values.
abstract final class JetDataSourceFile {
  /// The current document schema version.
  static const int version = 1;

  /// Encodes [doc] to a JSON-safe map stamped `jetDataSource: version`.
  static Map<String, Object?> encode(JetDataSourceDocument doc) =>
      <String, Object?>{
        'jetDataSource': version,
        'schema': _encodeSchema(doc.schema),
        if (doc.sample != null) 'sample': doc.sample,
      };

  /// Decodes a [json] map into a [JetDataSourceDocument]. Throws
  /// [JetDataSourceFormatException] on a missing/too-new version, a malformed
  /// shape, or an unknown field type.
  static JetDataSourceDocument decode(Map<String, Object?> json) {
    final Object? v = json['jetDataSource'];
    if (v is! int) {
      throw const JetDataSourceFormatException(
          'Missing or non-integer "jetDataSource" version.');
    }
    if (v > version) {
      throw JetDataSourceFormatException(
          'Document version $v is newer than this build ($version).');
    }
    final Object? rawSchema = json['schema'];
    if (rawSchema is! Map) {
      throw const JetDataSourceFormatException('Missing "schema" object.');
    }
    final JetDataSchema schema =
        _decodeSchema(rawSchema.cast<String, Object?>());
    final Object? rawSample = json['sample'];
    List<Map<String, Object?>>? sample;
    if (rawSample != null) {
      if (rawSample is! List) {
        throw const JetDataSourceFormatException('"sample" must be a list.');
      }
      sample = <Map<String, Object?>>[
        for (final Object? row in rawSample)
          if (row is Map)
            row.cast<String, Object?>()
          else
            throw const JetDataSourceFormatException(
                '"sample" rows must be objects.'),
      ];
    }
    return JetDataSourceDocument(schema: schema, sample: sample);
  }

  /// Encodes [doc] to a UTF-8 JSON string.
  static String encodeJson(JetDataSourceDocument doc) => jsonEncode(encode(doc));

  /// Decodes a UTF-8 JSON [source] string. Throws [JetDataSourceFormatException]
  /// when the text is not a JSON object.
  static JetDataSourceDocument decodeJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const JetDataSourceFormatException(
          'Data source JSON must be a JSON object.');
    }
    return decode(decoded.cast<String, Object?>());
  }
}

Map<String, Object?> _encodeSchema(JetDataSchema schema) => <String, Object?>{
      'name': schema.name,
      'fields': <Map<String, Object?>>[
        for (final FieldDef f in schema.fields) _encodeField(f),
      ],
    };

JetDataSchema _decodeSchema(Map<String, Object?> json) {
  final Object? name = json['name'];
  if (name is! String) {
    throw const JetDataSourceFormatException('Schema "name" must be a string.');
  }
  final Object? fields = json['fields'];
  if (fields is! List) {
    throw const JetDataSourceFormatException('Schema "fields" must be a list.');
  }
  return JetDataSchema(
    name: name,
    fields: <FieldDef>[
      for (final Object? f in fields)
        if (f is Map)
          _decodeField(f.cast<String, Object?>())
        else
          throw const JetDataSourceFormatException('Each field must be an object.'),
    ],
  );
}

Map<String, Object?> _encodeField(FieldDef field) => <String, Object?>{
      'name': field.name,
      'type': field.type.name,
      if (field.type == JetFieldType.collection)
        'fields': <Map<String, Object?>>[
          for (final FieldDef child in field.fields) _encodeField(child),
        ],
    };

FieldDef _decodeField(Map<String, Object?> json) {
  final Object? name = json['name'];
  if (name is! String) {
    throw const JetDataSourceFormatException('Field "name" must be a string.');
  }
  final Object? typeName = json['type'];
  final JetFieldType? type = JetFieldType.values
      .where((JetFieldType t) => t.name == typeName)
      .firstOrNull;
  if (type == null) {
    throw JetDataSourceFormatException('Unknown field type "$typeName".');
  }
  final Object? children = json['fields'];
  return FieldDef(
    name,
    type: type,
    fields: <FieldDef>[
      if (children is List)
        for (final Object? c in children)
          if (c is Map) _decodeField(c.cast<String, Object?>()),
    ],
  );
}
```

> Note: `firstOrNull` comes from `package:collection`'s extension, already a transitive dep, but to avoid a new import use the inline guard above (the `.where(...).firstOrNull` reads cleanly only if `collection` is imported). If `firstOrNull` is unavailable, replace the lookup with:
> ```dart
> JetFieldType? type;
> for (final JetFieldType t in JetFieldType.values) {
>   if (t.name == typeName) { type = t; break; }
> }
> ```
> Prefer the explicit loop to keep imports minimal.

- [ ] **Step 5: Add exports**

In `packages/jet_print/lib/jet_print.dart`, near the other `data/` exports, add:

```dart
export 'src/data/serialization/data_source_file.dart'
    show JetDataSourceDocument, JetDataSourceFile;
export 'src/data/serialization/data_source_format_exception.dart'
    show JetDataSourceFormatException;
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/serialization/data_source_file_test.dart`
Expected: PASS (6 tests). Replace the `firstOrNull` lookup with the explicit loop if analysis flags it.

- [ ] **Step 7: Analyzer + format gate**

Run: `cd packages/jet_print && dart format lib/src/data/serialization test/data/serialization && dart analyze lib/src/data/serialization`
Expected: formatted, no analyzer issues.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/serialization packages/jet_print/lib/jet_print.dart packages/jet_print/test/data/serialization
git commit -m "feat(data): JetDataSourceFile codec for *.jetreport.datasource"
```

---

## Task 2: `onSelectDataSchema` callback (designer + workspace + scope)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_designer.dart`
- Modify: `packages/jet_print/lib/src/designer/jet_report_workspace.dart`
- Modify: `packages/jet_print/lib/src/designer/designer_schema_scope.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Test: `packages/jet_print/test/designer/select_data_source_test.dart`

**Interfaces:**
- Consumes: `_guard` (already in `_JetReportDesignerState`), `ReportErrorCallback`.
- Produces:
  - `typedef ReportSelectDataSourceCallback = FutureOr<void> Function();`
  - `JetReportDesigner.onSelectDataSchema` / `JetReportWorkspace.onSelectDataSchema` (`ReportSelectDataSourceCallback?`).
  - `DesignerSchemaScope({required JetDataSchema? dataSchema, VoidCallback? onSelectDataSource, ...})` + `static VoidCallback? selectCallbackOf(BuildContext)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/select_data_source_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  testWidgets('workspace forwards onSelectDataSchema; guard routes throw to onError',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: emptyTestDefinition());
    addTearDown(controller.dispose);

    Object? captured;
    await tester.pumpWidget(MaterialApp(
      home: JetReportWorkspace(
        controller: controller,
        renderReport: (_) async => throw UnimplementedError(),
        onSelectDataSchema: () => throw StateError('boom'),
        onError: (Object error, StackTrace _) => captured = error,
      ),
    ));
    await tester.pumpAndSettle();

    // No schema + wired callback ⇒ the Data Source panel shows the button.
    final Finder button = find.byKey(
        const ValueKey<String>('jet_print.dataSource.selectButton'));
    // The Data Source tab may need selecting depending on layout; the panel is
    // present in the wide layout. Guard: only tap if found.
    expect(button, findsWidgets);
    await tester.tap(button.first);
    await tester.pump();
    expect(captured, isA<StateError>());
  });
}

/// A minimal blank definition for the test (single empty body).
ReportDefinition emptyTestDefinition() => ReportDefinition(
      furniture: const PageFurniture(),
      body: const ReportBody(scope: null),
    );
```

> The test author MUST first read `test/designer/` for the project's existing
> blank-definition helper (e.g. how `acceptance_invoice_from_blank_test.dart`
> builds an empty `ReportDefinition`) and reuse it instead of `emptyTestDefinition`
> above if one exists. Match the real `ReportDefinition`/`ReportBody` constructor
> shape — the snippet is illustrative.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/select_data_source_test.dart`
Expected: FAIL — `onSelectDataSchema` not a parameter / button key not found.

- [ ] **Step 3: Add the typedef + field in `jet_report_designer.dart`**

Near the other typedefs (after `ReportOpenRequestedCallback`, ~line 32):

```dart
/// Invoked when the author taps "Select data source" in an empty Data Source
/// panel. The host picks a `*.jetreport.datasource` file, decodes it with
/// [JetDataSourceFile], and attaches the resulting schema (e.g. by updating the
/// [JetReportDesigner.dataSchema] it passes). The library does no file I/O.
typedef ReportSelectDataSourceCallback = FutureOr<void> Function();
```

In the `JetReportDesigner` constructor params (next to `this.onOpenRequested`):

```dart
    this.onSelectDataSchema,
```

In the fields block (next to `onOpenRequested`):

```dart
  /// Invoked when the author taps "Select data source" in an empty Data Source
  /// panel; null ⇒ no button is shown. Routed through the error guard.
  final ReportSelectDataSourceCallback? onSelectDataSchema;
```

- [ ] **Step 4: Wire the guarded callback into the scope (`jet_report_designer.dart`)**

Change the `DesignerSchemaScope` construction (currently `DesignerSchemaScope(dataSchema: widget.dataSchema, child: ...)`, ~line 283) to also pass the guarded callback:

```dart
    return DesignerSchemaScope(
      dataSchema: widget.dataSchema,
      onSelectDataSource: widget.onSelectDataSchema == null
          ? null
          : () => _guard(() => widget.onSelectDataSchema!()),
      child: DesignerFontScope(
```

- [ ] **Step 5: Carry the callback in `designer_schema_scope.dart`**

Replace the class body to add the callback field, accessor, and notify rule:

```dart
class DesignerSchemaScope extends InheritedWidget {
  /// Shares [dataSchema] (nullable — null means no source attached) and an
  /// optional [onSelectDataSource] action with [child].
  const DesignerSchemaScope({
    required this.dataSchema,
    this.onSelectDataSource,
    required super.child,
    super.key,
  });

  /// The attached data-source structure, or null when none is attached.
  final JetDataSchema? dataSchema;

  /// The guarded "select a data source" action, or null when the host wired
  /// none. Shown by the Data Source panel only when [dataSchema] is null.
  final VoidCallback? onSelectDataSource;

  /// The nearest attached schema above [context], or null. Subscribes the caller.
  static JetDataSchema? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesignerSchemaScope>()
      ?.dataSchema;

  /// The nearest wired select-data-source action above [context], or null.
  static VoidCallback? selectCallbackOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesignerSchemaScope>()
      ?.onSelectDataSource;

  @override
  bool updateShouldNotify(DesignerSchemaScope oldWidget) =>
      oldWidget.dataSchema != dataSchema ||
      oldWidget.onSelectDataSource != onSelectDataSource;
}
```

Add the import `import 'package:flutter/widgets.dart';` is already present; `VoidCallback` comes from it.

- [ ] **Step 6: Add the field + forward in `jet_report_workspace.dart`**

Constructor param (next to `this.onOpenRequested`):

```dart
    this.onSelectDataSchema,
```

Field (next to `onOpenRequested`):

```dart
  /// Forwarded to [JetReportDesigner.onSelectDataSchema]: invoked when the
  /// author taps "Select data source" in an empty Data Source panel.
  final ReportSelectDataSourceCallback? onSelectDataSchema;
```

In the `build` where it constructs the nested `JetReportDesigner` (next to `onOpenRequested: widget.onOpenRequested,`, ~line 187):

```dart
          onSelectDataSchema: widget.onSelectDataSchema,
```

- [ ] **Step 7: Export the typedef**

In `packages/jet_print/lib/jet_print.dart`, extend the existing `jet_report_designer.dart` export `show` list (or add one) to include `ReportSelectDataSourceCallback`. Find the line exporting `jet_report_designer.dart` and add the name to its `show`.

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/select_data_source_test.dart`
Expected: PASS (depends on the panel button from Task 3 — if the button does not yet exist, this test's button assertion fails; implement Task 3 before re-running, or split: keep only the forwarding assertion green here by asserting `find.byType(JetReportWorkspace)` builds without error and defer the tap assertion to Task 3's test). **Recommended:** move the button-tap assertion to Task 3 and keep Task 2's test to construction-only forwarding (no throw on build with the callback wired).

- [ ] **Step 9: Analyzer + format gate**

Run: `cd packages/jet_print && dart format lib/src/designer test/designer/select_data_source_test.dart && dart analyze lib/src/designer`
Expected: clean.

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer packages/jet_print/lib/jet_print.dart packages/jet_print/test/designer/select_data_source_test.dart
git commit -m "feat(designer): onSelectDataSchema host callback + scope plumbing"
```

---

## Task 3: Data Source panel "Select data source" button + l10n

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_en.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_de.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_tr.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`
- Test: `packages/jet_print/test/designer/select_data_source_test.dart` (extend)

**Interfaces:**
- Consumes: `DesignerSchemaScope.of` / `DesignerSchemaScope.selectCallbackOf` (Task 2), `JetPrintLocalizations.dataSourceSelect` (this task).
- Produces: a `ShadButton` keyed `ValueKey<String>('jet_print.dataSource.selectButton')` rendered in the empty state when a select callback is wired.

- [ ] **Step 1: Add the localization string (abstract + 3 concrete + 3 arb)**

In `jet_print_localizations.dart`, next to `String get dataSourceEmpty;` (~line 276):

```dart
  /// Label of the button shown in the empty Data Source panel that lets the
  /// author attach a data source (`*.jetreport.datasource`).
  String get dataSourceSelect;
```

In `jet_print_localizations_en.dart` (next to `dataSourceEmpty`):

```dart
  @override
  String get dataSourceSelect => 'Select data source';
```

In `jet_print_localizations_de.dart`:

```dart
  @override
  String get dataSourceSelect => 'Datenquelle auswählen';
```

In `jet_print_localizations_tr.dart`:

```dart
  @override
  String get dataSourceSelect => 'Veri kaynağı seç';
```

In `jet_print_en.arb` (after the `dataSourceEmpty` entry + its `@`):

```json
  "dataSourceSelect": "Select data source",
  "@dataSourceSelect": {
    "description": "Button in the empty Data Source panel that lets the author attach a *.jetreport.datasource file."
  },
```

In `jet_print_de.arb`:

```json
  "dataSourceSelect": "Datenquelle auswählen",
  "@dataSourceSelect": {
    "description": "Button in the empty Data Source panel that lets the author attach a *.jetreport.datasource file."
  },
```

In `jet_print_tr.arb`:

```json
  "dataSourceSelect": "Veri kaynağı seç",
  "@dataSourceSelect": {
    "description": "Button in the empty Data Source panel that lets the author attach a *.jetreport.datasource file."
  },
```

> Mind JSON comma placement: add a trailing comma after the previous entry's closing `}` if `dataSourceEmpty`'s `@` block was the last key.

- [ ] **Step 2: Write the failing widget tests (extend the Task 2 test file)**

Append to `packages/jet_print/test/designer/select_data_source_test.dart`:

```dart
  testWidgets('empty panel + wired callback shows the button and tapping invokes it',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: emptyTestDefinition());
    addTearDown(controller.dispose);
    int taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: JetReportWorkspace(
        controller: controller,
        renderReport: (_) async => throw UnimplementedError(),
        onSelectDataSchema: () => taps++,
      ),
    ));
    await tester.pumpAndSettle();
    final Finder button = find.byKey(
        const ValueKey<String>('jet_print.dataSource.selectButton'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('empty panel without a wired callback shows no button',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: emptyTestDefinition());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: JetReportWorkspace(
        controller: controller,
        renderReport: (_) async => throw UnimplementedError(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.dataSource.selectButton')),
        findsNothing);
  });
```

> If the Data Source panel is behind a tab in the default layout, the test must
> first activate that tab. Read `test/designer/` for how existing panel tests
> reach the Data Source tab (e.g. `band_collection_binding_test.dart`) and mirror
> that navigation before asserting on the button.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/select_data_source_test.dart`
Expected: FAIL — button key not found.

- [ ] **Step 4: Implement the empty-state button in `data_source_panel.dart`**

Replace the `build` empty-state branch:

```dart
  @override
  Widget build(BuildContext context) {
    final JetDataSchema? schema = DesignerSchemaScope.of(context);
    if (schema == null) {
      final VoidCallback? onSelect =
          DesignerSchemaScope.selectCallbackOf(context);
      if (onSelect == null) {
        return RegionEmptyHint(
          icon: LucideIcons.database,
          message: JetPrintLocalizations.of(context).dataSourceEmpty,
        );
      }
      return _SelectDataSourcePrompt(onSelect: onSelect);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[_datasetNode(schema)],
      ),
    );
  }
```

Add the prompt widget at the bottom of the file:

```dart
/// Empty-state prompt shown when no data source is attached but the host wired
/// a select action: a short hint plus a "Select data source" button.
class _SelectDataSourcePrompt extends StatelessWidget {
  const _SelectDataSourcePrompt({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(LucideIcons.database,
                size: 28, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 12),
            Text(
              l10n.dataSourceEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
            const SizedBox(height: 16),
            ShadButton(
              key: const ValueKey<String>('jet_print.dataSource.selectButton'),
              onPressed: onSelect,
              leading: const Icon(LucideIcons.database, size: 16),
              child: Text(l10n.dataSourceSelect),
            ),
          ],
        ),
      ),
    );
  }
}
```

Ensure imports at the top of `data_source_panel.dart` include `ShadThemeData`/`ShadButton` (from `shadcn_ui`, already imported) — no new import needed (the file already imports `shadcn_ui`).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/select_data_source_test.dart`
Expected: PASS (all panel + forwarding cases).

- [ ] **Step 6: Full lib suite + format/analyze gate**

Run: `cd packages/jet_print && dart format lib/src/designer/layout/panels/data_source_panel.dart lib/src/designer/l10n && dart analyze lib && flutter test --exclude-tags golden`
Expected: format clean, analyzer clean, all tests green (no golden change).

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart packages/jet_print/lib/src/designer/l10n packages/jet_print/test/designer/select_data_source_test.dart
git commit -m "feat(designer): Select data source button in empty Data Source panel"
```

---

## Task 4: Playground Empty demo wiring + sample file

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`
- Create: `apps/jet_print_playground/sample_data/invoice.jetreport.datasource`
- Test: (manual GUI walk; plus an optional smoke assertion below)

**Interfaces:**
- Consumes: `JetDataSourceFile.decodeJson` (Task 1), `JetReportWorkspace.onSelectDataSchema` (Task 2).
- Produces: an Empty demo that starts with **no** schema and attaches one via the picker.

- [ ] **Step 1: Make `_DesignerTab.dataSchema` nullable + add a select flag**

In `apps/jet_print_playground/lib/main.dart`, change the `_DesignerTab` field and constructor:

```dart
  /// The data structure bound in this tab, or null when the tab starts with no
  /// data source (the Empty tab, which attaches one via "Select data source").
  final JetDataSchema? dataSchema;

  /// Whether this tab offers the "Select data source" action. Only the Empty
  /// tab does; the sample demos ship their own schema and leave it unwired.
  final bool enableSelectDataSource;
```

Add `this.enableSelectDataSource = false,` to the constructor (next to `this.enableFileIo = false,`).

- [ ] **Step 2: Hold the schema in tab state**

In `_DesignerTabState`, add:

```dart
  /// The live data source for this tab — seeded from the widget and replaced
  /// when the author attaches one via "Select data source".
  JetDataSchema? _schema;

  @override
  void initState() {
    super.initState();
    _schema = widget.dataSchema;
  }
```

(If `initState` already exists, add the `_schema = widget.dataSchema;` line into it.)

- [ ] **Step 3: Add the picker handler**

In `_DesignerTabState`, add the data-source file type and the handler near `_open`:

```dart
  /// The data-source file the Empty tab attaches: a `*.jetreport.datasource`
  /// JSON document decoded by [JetDataSourceFile].
  static const XTypeGroup _dataSourceType = XTypeGroup(
    label: 'Jet data source',
    extensions: <String>['datasource', 'json'],
  );

  /// Select a data source: pick a `*.jetreport.datasource` file, decode it, and
  /// attach its schema. Decode failures surface through the workspace onError.
  Future<void> _selectDataSource() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_dataSourceType],
    );
    if (file == null) return; // user cancelled
    final JetDataSourceDocument doc =
        JetDataSourceFile.decodeJson(await file.readAsString());
    setState(() => _schema = doc.schema);
  }
```

- [ ] **Step 4: Pass state + callback into the workspace**

In `_DesignerTabState.build`, change `dataSchema: widget.dataSchema,` to `dataSchema: _schema,` and add the callback:

```dart
      dataSchema: _schema,
      // ...
      onSelectDataSchema:
          widget.enableSelectDataSource ? _selectDataSource : null,
```

- [ ] **Step 5: Flip the Empty demo to start sourceless**

Change the `bos` demo body (and the `tab` helper to allow nullable schema + the flag). Update the `tab` helper:

```dart
    _DesignerTab tab(ReportDefinition seed, JetDataSchema? schema,
            RenderedReport Function(ReportDefinition) render,
            {bool fileIo = false, bool selectDataSource = false}) =>
        _DesignerTab(
            fonts: widget.fonts,
            seed: seed,
            dataSchema: schema,
            renderReport: render,
            enableFileIo: fileIo,
            enableSelectDataSource: selectDataSource);
```

And the `bos` entry:

```dart
        body: tab(emptyDesignDefinition(), null,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts),
            fileIo: true, selectDataSource: true),
```

> The render callback still uses `renderInvoiceDefinition` so Preview works with
> the bundled invoice sample data; consuming the selected file's `sample` rows in
> Preview is an explicit non-goal of this slice.

- [ ] **Step 6: Create the sample data-source file**

Create `apps/jet_print_playground/sample_data/invoice.jetreport.datasource`:

```json
{
  "jetDataSource": 1,
  "schema": {
    "name": "Invoice",
    "fields": [
      { "name": "number", "type": "string" },
      { "name": "date", "type": "dateTime" },
      { "name": "customer", "type": "string" },
      { "name": "total", "type": "double" },
      {
        "name": "lines",
        "type": "collection",
        "fields": [
          { "name": "description", "type": "string" },
          { "name": "qty", "type": "integer" },
          { "name": "unitPrice", "type": "double" },
          { "name": "lineTotal", "type": "double" }
        ]
      }
    ]
  },
  "sample": [
    {
      "number": "INV-001",
      "customer": "Acme Co.",
      "total": 240.0,
      "lines": [
        { "description": "Widget", "qty": 2, "unitPrice": 50.0, "lineTotal": 100.0 },
        { "description": "Gadget", "qty": 1, "unitPrice": 140.0, "lineTotal": 140.0 }
      ]
    }
  ]
}
```

- [ ] **Step 7: Optional smoke test**

If `apps/jet_print_playground/test/` exists, add `apps/jet_print_playground/test/sample_data_source_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('bundled sample invoice.jetreport.datasource decodes', () {
    final String text =
        File('sample_data/invoice.jetreport.datasource').readAsStringSync();
    final JetDataSourceDocument doc = JetDataSourceFile.decodeJson(text);
    expect(doc.schema.name, 'Invoice');
    expect(doc.schema.fields.any((FieldDef f) => f.name == 'lines'), isTrue);
    expect(doc.sample, isNotNull);
  });
}
```

Run: `cd apps/jet_print_playground && flutter test test/sample_data_source_test.dart`
Expected: PASS. (Skip this step if the playground has no `test/` dir; the manual walk covers it.)

- [ ] **Step 8: Build + analyze the playground**

Run: `cd apps/jet_print_playground && dart format lib/main.dart && flutter analyze && flutter test`
Expected: format clean, analyzer clean, existing playground tests green.

- [ ] **Step 9: Manual GUI walk**

Run the playground (`cd apps/jet_print_playground && flutter run -d macos`), open the **Empty** (Boş) tab:
- Data Source panel shows the **Select data source** button (not just the empty hint).
- Tapping it opens a file picker; choose `sample_data/invoice.jetreport.datasource`.
- The panel now shows the `Invoice` dataset tree with the `lines` collection; fields are draggable/bindable.
- Picking a malformed file surfaces an error via the existing error path (no crash).

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/sample_data
git add apps/jet_print_playground/test/sample_data_source_test.dart 2>/dev/null || true
git commit -m "feat(playground): Empty demo attaches a data source via Select"
```

---

## Self-Review

**Spec coverage:**
- Codec (`JetDataSourceFile`, schema + optional sample, versioned, typed exception) → Task 1. ✓
- `onSelectDataSchema` callback on designer + workspace, `_guard`-wrapped, scope-carried → Task 2. ✓
- Panel empty-state button gated on (no schema ∧ wired callback); else unchanged hint → Task 3. ✓
- Localized label `dataSourceSelect` (abstract + en/de/tr + 3 arb) → Task 3. ✓
- Playground Empty demo: nullable schema state, picker, decode, sample file → Task 4. ✓
- Non-goals (visual schema editor, live preview from sample, render/golden change) → respected (Task 4 Step 5 note; widget-only tests). ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. Two illustrative-snippet caveats (the blank-`ReportDefinition` helper in Tasks 2/3 and the Data Source tab navigation) explicitly instruct the implementer to read existing tests and mirror the real shape — necessary because the exact blank-definition constructor + panel-tab navigation are codebase conventions to be matched, not invented.

**Type consistency:** `JetDataSourceDocument` / `JetDataSourceFile` / `JetDataSourceFormatException` consistent across Tasks 1 & 4. `onSelectDataSchema` (public field, both designer + workspace) vs `onSelectDataSource` (the guarded `VoidCallback` inside `DesignerSchemaScope`) — names intentionally distinct (one is the host hook, the other the already-guarded scope action); used consistently. Button key `jet_print.dataSource.selectButton` identical in Tasks 2/3. `dataSourceSelect` getter identical across all l10n files.

**Note on Task 2 ↔ Task 3 ordering:** Task 2's tap assertion depends on Task 3's button. Resolved in Task 2 Step 8: keep Task 2's test to forwarding/construction only and place the tap+invoke assertions in Task 3. Implement in order 1→2→3→4.
