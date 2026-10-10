# Storing a report definition

Can a consumer of the published package store a report definition and read it
back? Yes — `JetReportFormat` is exported with all four of its statics, so a
host that keeps templates in files has everything it needs, and the playground
proves it through the barrel alone. What is missing is narrower and shows up
only once the store is a database rather than a disk: nothing public named the
schema version being written (fixed in `c4a7f8d`, below), every decode failure
arrives as one exception type carrying one English string, and a migration
leaves no trace.

The difference is who owns the file. A desktop host writes a document the same
user opens minutes later on the same build; if the decode throws, a dialog says
so and the user picks another file. A multi-tenant application stores one row
per tenant, written months ago by a build since superseded, and read back by
whichever build that tenant happens to be running during a staged rollout. It
must answer *which version wrote this*, *is this row from the future or is it
corrupt*, and *which rows still need upgrading* — the three questions the
public surface does not answer. This page is an input to the P4 freeze review
named in [`roadmap.md`](roadmap.md), beside
[`api-friction.md`](api-friction.md).

## The exported surface, name by name

`packages/jet_print/lib/jet_print.dart` is the precise public surface. Seven of
its `export` directives bear on serialization, versioning or JSON:

| Directive | Names shown |
|---|---|
| `src/domain/serialization/report_format.dart` | `JetReportFormat` |
| `src/domain/serialization/report_format_exception.dart` | `ReportFormatException` |
| `src/domain/unknown_element.dart` | `UnknownElement` |
| `src/domain/detail_scope.dart` | `UnknownScopeNode`, among the other node kinds |
| `src/data/serialization/data_source_file.dart` | `JetDataSourceDocument`, `JetDataSourceFile` |
| `src/data/serialization/data_source_format_exception.dart` | `JetDataSourceFormatException` |
| `src/version.dart` | `jetPrintVersion` |

`src/data/json_data_source.dart` → `JetJsonDataSource` is the eighth name with
JSON in it and is out of scope: it ingests rows to render against, not
definitions to persist. Showing a class shows its members, so
`JetReportFormat.encodeDefinition`, `decodeDefinition`, `encodeDefinitionJson`
and `decodeDefinitionJson` are all public. `jetPrintVersion` is the package
version string, not the schema number.

Not exported, from the same directories: `ElementCodec` and
`ElementCodecRegistry`, `registerBuiltInElementCodecs`, `SchemaMigration`,
`runMigrations`, `V1ToV2Migration`, the top-level `encodeDefinition` /
`decodeDefinition` functions in `report_definition_codec.dart` — and, in that
same file, the constant `kReportDefinitionSchemaVersion`. The codec and
migration types being internal is settled and deliberate:
[`decisions/0002`](decisions/0002-extension-seam-closed-for-1-0.md) decided it.
The constant is not part of that decision, and is the omission below that costs
a consumer most.

## The round trip is real, and first-party code uses it through the barrel

[`domain/serialization/report_format.dart`](../packages/jet_print/lib/src/domain/serialization/report_format.dart)
→ `JetReportFormat` is `abstract final`, builds its `ElementCodecRegistry` in a
private static initialiser and holds its own `_definitionMigrations` list. A
consumer assembles nothing.

`apps/jet_print_playground/lib/main.dart` imports
`package:jet_print/jet_print.dart` and no `src/` path. Its `_save` calls
`JetReportFormat.encodeDefinitionJson`; its `_open` calls
`_controller.open(JetReportFormat.decodeDefinitionJson(contents))`. That is
worth stating plainly because the opposite would have been the finding — a
first-party app reaching into `src/` for save and load would mean the barrel
was short. It does not, and it is not.

The designer is served in both directions.
[`designer/jet_report_designer.dart`](../packages/jet_print/lib/src/designer/jet_report_designer.dart)
→ `JetReportDesigner` takes `initialReport` as a `ReportDefinition?`, so a host
seeds the editor from a decoded row without touching a controller, and
`onSaveRequested` is invoked by `_JetReportDesignerState.build` with
`_controller.definition` — a public getter whose dartdoc calls it "the value a
host saves". The widget's own dartdoc example already writes the idiom a
database host wants, with `writeFile` and `readFile` where the repository calls
would go, and host callbacks run inside `_JetReportDesignerState._guard`, so a
throw or a rejected Future from save or open reaches `onError` rather than
escaping.

## Three places it stops short of a database

**One: nothing public names the schema version.** *Fixed* in `c4a7f8d`,
before 0.1.0 was published: `JetReportFormat.schemaVersion` is a public `const`
equal to `kReportDefinitionSchemaVersion`, the barrel-only test named below
reads it instead of reconstructing it, and `test/public_api_test.dart` pins it
against the key the encoder stamps. The rest of this point records the gap as
it stood.
`report_definition_codec.dart` → `kReportDefinitionSchemaVersion` is `2` and is
stamped as the first key of every document, but it is a top-level constant in
an unexported library and `JetReportFormat` does not re-expose it. A consumer
wanting a `schema_version` column, an index on it, or a query for the rows a
back-fill has yet to touch must either hard-code the string `'schemaVersion'`
and the integer, or encode a throwaway definition and read the key back. The
library's own barrel-only test does the second:
`test/domain/serialization/report_format_test.dart`, *throws
ReportFormatException on a version newer than the build*, obtains the number as
`JetReportFormat.encodeDefinition(_fixture())['schemaVersion']! as int`. A test
that exists to prove the public surface sufficient, reconstructing a constant,
is the surface reporting a hole in itself.

The sibling format has no such hole.
[`data/serialization/data_source_file.dart`](../packages/jet_print/lib/src/data/serialization/data_source_file.dart)
→ `JetDataSourceFile.version` is a public static on an exported class. A host
can read the data-source document version it writes and cannot read the report
one, for no reason the code gives.

**Two: every decode failure is one type carrying one string.**
`report_format_exception.dart` → `ReportFormatException` has a single field,
`message`. Two outcomes a multi-tenant host must treat completely differently
are indistinguishable through it. A `schemaVersion` greater than this build's —
which `decodeDefinition` rejects before attempting anything else — is routine
and recoverable during a rollout: the row is fine, the client is behind, and
the response is to tell the user to reload. A structural fault is a damaged
row, and the response is to restore it. Telling them apart today means
substring-matching `'is newer than this build supports'`, an interpolated
English sentence that no test pins and that a reword or a localisation would
break.

**Three: a migration leaves no trace a consumer can read.**
Forward migration needs no public entry point: `decodeDefinition` calls
`runMigrations` itself whenever `rawVersion` is below the current one, so a
consumer loading a v1 row gets a v2 `ReportDefinition` back without asking, and
that part is right. What comes back is a bare `ReportDefinition` with no signal
that an upgrade happened. A host wanting to write migrated rows back — the
ordinary thing to do, since [`06-round-tripping.md`](06-round-tripping.md)
records that `V1ToV2Migration` is an upgrade rather than a round trip and keeps
only the first band of each chrome slot — must decide by reading the raw key
itself, against a number it hard-coded.

Unrecognised content is detectable, with work: `UnknownElement`,
`UnknownScopeNode` and every node type needed to walk a definition are
exported, so a host finds them by recursion and reads `typeKey`. There is no
shortcut. `validate()` emits an `info` `Diagnostic` for an `UnknownScopeNode`
and nothing at all for an `UnknownElement`, and `Diagnostic` carries
`severity`, `message` and `elementId` but no code.

## What a consumer must do today

Persisting a report from a database-backed host, with only the barrel:

```dart
// Save: the definition arrives from the designer, already public.
onSaveRequested: (ReportDefinition d) => db.upsert(
      tenantId,
      JetReportFormat.encodeDefinitionJson(d),
      // Before c4a7f8d this was a hard-coded 2.
      schemaVersion: JetReportFormat.schemaVersion,
    );

// Load: one error type, and a string match to classify it.
try {
  return JetReportFormat.decodeDefinitionJson(await db.fetch(tenantId));
} on ReportFormatException catch (e) {
  if (e.message.contains('newer than this build')) throw ClientOutOfDate();
  throw TemplateCorrupt(e.message);
}
```

The version no longer needs a workaround. The string match still does, and it
is not exotic or expensive. It is written once, in one repository helper, and
owned forever — which is the cost, because the matched sentence is then a fact
about `jet_print` living in somebody else's code, maintained by somebody who
will not read the changelog entry when it moves. The hard-coded `2` had the
same cost until `c4a7f8d`. The README's *Save and reopen designs* section shows
the round trip to a JSON string and, since `c4a7f8d`, names
`JetReportFormat.schemaVersion` and says a newer document throws
`ReportFormatException`; it does not say how to tell that from a corrupt one,
because nothing public can yet.

## What would have to be exported

Two things, and a third that needs nothing, none of which touches the
boundary `decisions/0002` drew:

- `kReportDefinitionSchemaVersion`, or the same integer as a static on
  `JetReportFormat` — matching `JetDataSourceFile.version`, which already does
  this for the other format. *Done* in `c4a7f8d`, as
  `JetReportFormat.schemaVersion`.
- Something on `ReportFormatException` that separates a too-new document from a
  structural fault: a subtype, or a nullable field carrying the document's
  version, either of which a host can branch on without reading prose.
- Nothing for migration. It is already automatic and already correct; it needs
  only the version constant above for a consumer to know which rows to re-save.

Making the documented error contract the true one — every malformed document
raising `ReportFormatException` — was the fourth item, and is done: `7535890`
routed both decode entry points through one boundary that converts `TypeError`,
`ArgumentError` and `FormatException`, and
`test/domain/serialization/malformed_input_test.dart` pins it.

## What it means for the 1.0 freeze

`decisions/0002` closed the extension seam on a stated test — opening it later
is additive, because exporting a type adds a name to the barrel and an optional
parameter to a call, and changes the meaning of no existing one. That is the
right test to apply here, and applied honestly both exports pass it. A static
constant is additive. A subtype of an exported exception is additive, since
`on ReportFormatException catch` keeps catching it. Nothing here
forecloses a fix in a `1.x` minor, and on the letter of the test this does not
block the freeze.

One asymmetry is worth naming before that is read as "no difference at all". A
closed extension seam costs a would-be extender their time; they meet it
immediately, and when it opens they use it. Stored JSON is not like that: a
tenant's row outlives the build that wrote it, and outlives the workaround the
consumer adopted for not being able to name its version. Hosts that hard-coded
a `2` and matched a sentence carry both into every later version, long after
the exports arrive.

That is a real difference in kind, and it is still not a blocker, for one
reason stated plainly rather than assumed: every document already carries
`schemaVersion` as its first key. A consumer that stored rows without a version
column can recover the number from the JSON itself at any time. The
irreversible form of this problem — data written without the information needed
to interpret it — does not arise, because the format was designed not to allow
it. What remains is a cost paid in other people's code, which argues for
closing it in P3 beside the friction list rather than after the semver promise,
and does not argue for holding the freeze.
