# The smallest report

The least a report definition can contain and still render, and what every
later chapter adds to it.

A definition with one band is a complete report. Groups, nested scopes, page
furniture, crosstabs, watermarks — everything else in the model is an addition
to that shape, never a precondition for it, and each page along the spine adds
exactly one thing to it. `ReportDefinition` in
[`domain/report_definition.dart`](../packages/jet_print/lib/src/domain/report_definition.dart)
takes three required values: a `name`, a `page`, and a `body`. Parameters,
variables and page furniture all default to empty.

## One band

[`test/support/report_builders.dart`](../packages/jet_print/test/support/report_builders.dart)
→ `oneBandReport` is that shape, written once as the shared seed for the
designer controller's edit-command tests:

```dart
ReportDefinition oneBandReport({
  List<ReportElement> elements = const <ReportElement>[],
  // ... name, bandId, bandHeight, page, type — defaults named below
}) =>
    ReportDefinition(
      name: name,
      page: page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: bandId,
              type: type,
              height: bandHeight,
              elements: elements,
            )),
          ],
        ),
      ),
    );
```

Four wrappers around one empty band, and every level is load-bearing:

- **`ReportDefinition`** names the report and fixes its `PageFormat`, which is
  required and never inferred. The builder's default is `PageFormat.a4Portrait`
  — 595.28 by 841.89, with uniform 28.35 margins, all in **points**, which is
  the model's only unit. No pixels, no millimetres: a band's `height` and an
  element's `bounds` are points too.
- **`ReportBody`** holds the data-driven content. Its once-per-report slots —
  `title`, `summary`, `noData` — are optional and omitted here.
- **`DetailScope`** with a null `collectionField` is the *master* scope: it
  iterates the rows the host supplies. A non-null `collectionField` would make
  it a nested scope over a child collection, which is page 02's subject.
- **`BandNode`** wraps a band printed once per row of the scope that owns it.

The remaining defaults are `'test'` for the report's name, `'detail'` and
`BandType.detail` for the band, a height of 120, and no elements at all. `type`
is not a free choice there: `domain/report_validation.dart` → `validate`
slot-checks every band against the slot holding it, and a `BandNode` child whose
type is not `BandType.detail` is an **error** diagnostic. The builder's default
is the one type that slot accepts. Elements are optional because what a band
first contributes to a page is its height.

Every node in that tree carries an `id`, and the ids are the addressing scheme
the whole designer is built on: `createElement(..., bandId: 'detail')`,
`setShapeKind('s1', ...)`, `selectGroup(group.id)` — selection and the edit
commands name their target by id rather than by index, so an edit survives the
node moving. That only works if ids are unique, which is why
`validate` counts every id it walks past and reports a repeat as an **error**.
`'root'` and `'detail'` in the excerpt are conventional slugs, not magic: a
fresh design is addressable the moment it exists.

## The one door

`lib/jet_print.dart` is the library's single public entry point: consumers
import `package:jet_print/jet_print.dart` and nothing else, and everything
under `lib/src/` is private to them. `test/encapsulation_test.dart` enforces
that by scanning import and export directives, and `test/public_api_test.dart`
proves the exported surface is sufficient to build, mutate, validate, serialize
and render a report.

`test/support/report_builders.dart` is bound by the same ban — it sits outside
the white-box allowlist `AGENTS.md` describes — so the excerpt above is
consumer-level code. Every type it names is public surface, and if one of them
stopped being exported the file would stop compiling.

## Why the model is a tree

The obvious alternative is the one banded-report tools have used for decades: a
flat list of bands, each declaring its role in a `type` field. It is easy to
read, easy to serialize, and it is what this model replaced. The inference it
required is not a memory: it still runs, in
`domain/serialization/migrations/v1_to_v2.dart` → `V1ToV2Migration`, which reads
a v1 band's `type`, its group name, its `collectionField` and its position to
work out which slot of the tree that band belongs in — four inputs to place one
band, exercised by `test/domain/serialization/migration_v1_to_v2_test.dart`.
That inference fails in three ways.

**Role becomes a guess.** When those four inputs disagree there is no right
answer, only whichever rule the code reading the list happens to apply — and the
filler, the layouter and the designer all read it. A tree has no such question:
a band in `PageFurniture.pageHeader` is a page header because of where it is,
and a band under a `GroupLevel`'s `footer` is a group footer for the same
reason.

**There is nothing to validate.** If a role is inferred, a misplaced band is not
wrong, merely inferred differently. Slots make the expectation nameable, which
is what lets `validate` compare a band's declared `type` against the slot
holding it and report a mismatch — a rule that cannot exist over a list with no
slots. `type` survives for labels, glyphs and migration; position is what is
authoritative.

**Order stops being data.** `DetailScope.children` is an *ordered* list of
`ScopeNode`s, so an author's interleaving of per-row bands and sub-scopes
survives editing and migration. A flat list has to rebuild that order by sorting
on type, and sorting cannot express an order the author chose.

`ScopeNode` is `sealed`, so a traversal switches over its four cases with no
default arm and a fifth kind of node fails to compile — the same
compiler-as-enforcement argument the frame makes for its primitives.

The costs are real. There is no index: you cannot ask a definition for "its
bands", you walk it, which is why `designer/controller/band_walker.dart` →
`mapBands` exists rather than every edit command re-implementing the descent.
And the tree is verbose to build by hand — four wrappers around one empty band
is why the tests share a builder instead of each writing the nesting out.

## Run it

```bash
flutter test packages/jet_print/test/public_api_test.dart
```

That file's own header says it "acts as an external consumer": it imports the
barrel and never `package:jet_print/src/...`, so what it does is exactly what a
host app can do. Several of its cases speak to the shape above.

The reified tree types — `ReportDefinition`, `ReportBody`, `DetailScope`,
`ScopeNode`, `BandNode`, `Band`, `BandType`, `PageFormat` — are all reachable
from the barrel, so a consumer can write this tree at all; the case proving it
assembles a richer definition than the excerpt, with furniture, a title, a
`GroupLevel` and a `NestedScope`, which is the same reachability argument with
more of it. `validate` is public and returns no error diagnostics for a one-band
definition. And `const JetReportEngine().renderDefinition(...)`, handed one of
those and a `JetInMemoryDataSource` holding a single empty row, returns a
`RenderedReport`: a band, a page and a row are the whole input the engine needs.
The remaining cases exercise the rest of the public surface — the controller's
mutators, the format round trip, the preview — each of which a later page takes
up.

`const` is not decoration:
[`rendering/engine/jet_report_engine.dart`](../packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart)
→ `JetReportEngine` declares no fields. `renderDefinition` builds one
`FontRegistry` for the render, calls `ReportFiller.fillDefinition` then
`ReportLayouter.layoutLazyDefinition` with the host's locale installed around
both, and returns a `RenderedReport` reading the three diagnostic sinks those
steps wrote — parameters, fill, layout. The facade owns no rendering logic, which
is why every later page names the filler, the layouter and the painters rather
than the engine, and it is where degrading beats throwing: a declared parameter
with neither a supplied value nor a default warns and resolves empty.

## What is not here yet

Each of these is one later page, and each is genuinely absent from the shape
above rather than merely defaulted.

- **No data.** The band holds no elements, and an element would not be bound
  either: a `TextElement` carries a literal `text` until its `expression` is
  non-null. Rows arrive at render time from a `JetDataSource`, not from the
  definition. → page 02.
- **No pagination.** Nothing in the model says which page anything lands on.
  The definition states a band's height in points; turning heights into pages is
  the layouter's work, done lazily per page. → page 03.
- **No geometry, no pixels.** A band is a height and a list of bounds, not a
  position on paper. Resolving those into a flat, absolutely-positioned
  `PageFrame` is what the pipeline exists to do (→ page 04), and drawing that
  frame to a canvas, a PNG or a PDF is the step after (→ page 05).
- **No file.** This definition lives in memory. Versioned JSON, migration, and
  the preservation of nodes a build does not recognize are → page 06.

One property worth carrying forward: the model is allowed to represent more than
the engine renders. Several per-row bands in one scope, or a scope node kind
this build has never heard of, are reported by `validate` as **info** — stated,
not silently reinterpreted, and not rejected either.

And `validate` only helps where something calls it. The designer calls it live —
`designer/controller/jet_report_designer_controller.dart` → `diagnostics` is
`validate(_document.definition)` — but the render path never does, so a definition
built in code and handed straight to the engine is checked by nothing unless a test
checks it. Commit `bc8cc9c` is the cost: a playground sample's heading band sat in
a per-row slot and printed sixteen times, once per data row, while the slot rule
naming that mistake sat unused in `report_validation.dart`. Validate what you add.

## Next

Page 02, [binding data](02-binding-data.md), gives this report something to say:
how `$F{}` and `{...}` expressions resolve against a row, how the master scope's
rows become a nested scope's collections, and where an aggregate folds.
