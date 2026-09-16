# Round-tripping

What survives when a report is written as JSON by one build and read back by another.

Pages 01–05 took a definition through data, pagination, the frame and the ink — all in
memory, on a value a host handed the engine. This page is about the file: authored by
a designer someone shipped last year, opened by one shipped today, or the reverse. The
contract is *Report JSON is versioned and lossless*, an `AGENTS.md` hard rule; below is
the machinery under it, and where it is narrower than the sentence sounds.

## One integer decides everything

[`domain/serialization/report_format.dart`](../packages/jet_print/lib/src/domain/serialization/report_format.dart)
→ `JetReportFormat` is the whole public surface: `encodeDefinition` /
`decodeDefinition` plus their JSON-text conveniences. It touches no files — a host
owns save and open — and pre-wires the built-in element codecs and the migration list.

The version is `domain/serialization/report_definition_codec.dart` →
`kReportDefinitionSchemaVersion`, currently `2`, stamped as the first key of every
document written. `decodeDefinition` reads it before anything else, and the three
branches are not symmetric. Not an `int` — missing, a string, a double — is a
`ReportFormatException`; greater than this build's is a `ReportFormatException` naming
both numbers, nothing else attempted; only *less than* reaches `runMigrations`.

An older file opens; a newer-versioned one does not. Which is how to read the rule: the
promise about a newer build's work surviving is not about a bumped `schemaVersion` at
all. It covers what a newer build adds *without* bumping it — a new element type, a new
scope-node kind — which still writes `schemaVersion: 2` and lands in this decoder.

## The registry that decides what a type means

Element dispatch is one map keyed by `typeKey`, in
[`domain/serialization/element_codec.dart`](../packages/jet_print/lib/src/domain/serialization/element_codec.dart)
→ `ElementCodecRegistry`. `register` is a plain `_codecs[typeKey] = codec`, so a later
registration for the same key replaces an earlier one — last write wins, the same rule
`rendering/elements/element_renderer_registry.dart` states for renderers.

```dart
// domain/serialization/element_codec.dart → ElementCodecRegistry.decode
// ... cut above: the `_codecs` field, `register` (the one-line map assignment),
// and `encode`, whose unknown-element arm is quoted in the next section.
ReportElement decode(Map<String, Object?> json) {
  final Object? typeKey = json['type'];
  if (typeKey is! String) {
    throw const ReportFormatException('Element JSON missing string "type".');
  }
  final ElementCodec<ReportElement>? codec = _codecs[typeKey];
  if (codec == null) {
    return UnknownElement(typeKey: typeKey, rawJson: _deepCopyJsonMap(json));
  }
  try {
    return codec.fromJson(json);
  } on ReportFormatException {
    rethrow;
  } catch (error) {
    throw ReportFormatException('Malformed "$typeKey" element: $error');
  }
}
```

A structural fault — no `type` string, or a codec that throws on its own fields — is
fatal; an unrecognized type is not a fault at all. The registry is also the only
extension point for a new element type, and today it extends the library rather than a
consumer: `lib/jet_print.dart` exports `JetReportFormat`, `ReportFormatException`,
`UnknownElement` and `UnknownScopeNode` but neither codec type, and `JetReportFormat`
builds its registry privately.

What that extension point buys is proven, and it is narrower than it sounds:
`test/rendering/elements/persisted_extension_test.dart` gives a `StarElement` its
own `ElementCodec` and `ElementRenderer`, registers both on an
`ElementTypeRegistry`, then round-trips it through `encodeDefinition` /
`decodeDefinition` and paints it — with **no edit anywhere under `lib/src/`**. It
reaches those registries through `package:jet_print/src/…` imports, which a
consumer cannot. No edits required; not open to everyone.

## What "preserved verbatim" preserves

Two types carry unrecognized JSON, and they preserve it differently.

```dart
// domain/serialization/element_codec.dart → ElementCodecRegistry.encode
if (element is UnknownElement) {
  return _deepCopyJsonMap(element.rawJson);
}

// domain/serialization/report_definition_codec.dart → _encodeNode
UnknownScopeNode(rawJson: final Map<String, Object?> raw) =>
  Map<String, Object?>.of(raw),
```

[`domain/unknown_element.dart`](../packages/jet_print/lib/src/domain/unknown_element.dart)
→ `UnknownElement` deep-copies in *and* out, so a caller mutating the map it decoded
from cannot reach the preserved copy. It reads `id`, `bounds` and `name` best-effort,
falling back to `''` and `JetRect.zero`, only so the thing can be drawn as
`rendering/elements/renderers/unknown_element_renderer.dart`'s placeholder.

The four edits the rule names are inert, and inert the same way: `withBounds`,
`withName` and `withVisible` — the polymorphic move/resize, rename and hide
primitives every designer command goes through — are each `=> this`. No path writes a
new position into the preserved map, because no path writes anything into it.

`domain/unknown_scope_node.dart` → `UnknownScopeNode` is the same idea one level up,
for an unrecognized `kind`, and preserves less tightly: the decoder hands it
`Map.unmodifiable(json)`, which freezes only the top level, and the encoder returns
`Map.of(raw)`, a shallow copy whose source comment gives the reason — handing back
`raw` would throw `UnsupportedError` in any caller post-processing the output. Nested
containers are the decoder's own objects; the dartdoc says do not mutate them.

Nothing offers to edit one, either. It carries no id this build can read, so
`designer/controller/band_walker.dart` → `reorderScopeNode` never matches it (it keeps
its relative position while siblings move around it) and the Outline's `rows.dart` adds
no row; every tree-rebuilding switch there passes it through as `=> n`, with a comment
recording why that arm is not a `break` — a `break` would delete the node on the next
designer edit. `validate()` reports it as **info**.

One clarification on the phrase, which the rule, several dartdocs and three test names
all use. Every round-trip test in `test/domain/serialization/` compares *maps* — the
re-encoded definition against the original under `equals`, deep value equality,
insensitive to key order; none compares JSON text. Key order survives mechanically,
both copy paths rebuilding the map in iteration order; it is not what is pinned.

## Forward only

`domain/serialization/migration.dart` → `SchemaMigration` is two members: the version
it upgrades *from*, and a pure `upgrade` map→map that must not mutate its input.
`runMigrations` loops one version at a time, picks the migration whose `fromVersion`
matches the step, and throws a `ReportFormatException` naming the step when none is
registered. There is no downgrade direction: `to` is always the current constant.

One migration exists, `V1ToV2Migration`, which page 01 already cited for what it
reveals about the pre-tree model. As a *format* change it is pure map surgery: element
maps are carried into their new band positions undecoded, and the output is stamped
`'schemaVersion': 2`. It is also where "lossless" stops being a property of migration
— it keeps the *first* band of each chrome slot and the first header/footer per group
name, rebuilding each band from `height` and `elements` alone, so a v1 document with
two page headers loses one. An upgrade, not a round-trip.

Adding a schema version means writing the `N → N+1` migration, adding it to
`JetReportFormat`'s list, and recording it in `packages/jet_print/CHANGELOG.md` — the
rule names all three.

## Why it is like this, and the alternative rejected

The short alternative is to reject what you do not understand: no `type` in the
registry, no `kind` in the switch, throw. Defensible for a wire protocol, wrong for a
document — the file is the user's work, and a build that refuses it turns a
colleague's newer designer, or a plugin someone uninstalled, into a file nobody can
open. The softer version — drop the node, open the rest — is worse: it opens cleanly,
looks right, and deletes on the next save, which is the `band_walker.dart` comment's
point at a smaller scale.

The cost is paid in editability, openly rather than approximated. An unknown element
could plausibly be moved — `bounds` is right there, and rewriting two numbers looks
harmless — but nothing here knows whether that map holds a second copy of its geometry
or a constraint tying it to a sibling. The no-op is the only edit that cannot be wrong.

## Run it

```bash
flutter test packages/jet_print/test/domain/serialization/
flutter test packages/jet_print/test/designer/controller/band_walker_test.dart
```

The first directory is what the rule names as its enforcement, and the interesting
cases are negative: a missing `schemaVersion` and a version one greater than the build
both throw; an unregistered `type` decodes to an `UnknownElement` and re-encodes to the
map it came from, even after that source map's nested list and bounds were mutated
underneath it. The second pins survival through a real *designer edit* — `addGroup`,
through the tree rebuilders — with the node's `rawJson` intact afterwards.

## Trap

**There are two built-in registration lists, and they have already drifted.**
`domain/serialization/built_in_element_codecs.dart` → `registerBuiltInElementCodecs`
registers four type keys — `text`, `shape`, `image`, `barcode` — and is the one
`JetReportFormat` wires. `rendering/elements/built_in_element_renderers.dart` →
`registerBuiltInElementTypes` registers five, pairing each codec with its renderer, the
fifth being `chart`. The two fail differently, which hides the gap:
`ElementRendererRegistry.rendererFor` *falls back* to the placeholder renderer, while
`ElementCodecRegistry.encode` **throws** `StateError` for a key it does not hold. So a
`ChartElement` renders, previews and exports normally, while
`JetReportFormat.encodeDefinition` throws `No ElementCodec registered for type "chart"`
— as does `designer/controller/element_clone.dart` → `cloneElement`, the duplicate and
paste primitive, which round-trips an element through that same registry. Register a new
type in both lists, or it renders everywhere and saves nowhere.

## Next

That closes the spine: a report defined, bound, paginated, framed, painted, and now
written and read back. What it has not covered is the surface a person actually touches
— the canvas, the command stack behind undo/redo, the inspectors, and how an edit
becomes a new definition without the designer forming a second opinion about how a
report looks. That sequence begins at `07-designer-loop.md`.
