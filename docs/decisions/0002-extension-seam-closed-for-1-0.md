# 0002 — The extension seam stays closed for 1.0

**Status:** Accepted — 2026-09-21

## Context

`jet_print` has no public way for a host to add an element type or an expression
function, and the current record of that fact is an aside inside a bug-fix entry.
`packages/jet_print/CHANGELOG.md`, under *Documentation: the element and
expression registries were described as host extension points they are not*,
ends:

> No behaviour changed; if you need to register a custom element type or
> expression function, that capability does not exist yet. Please open an issue.

The entry it closes is the correction itself: `JetFunctionRegistry`,
`ElementCodecRegistry`, `ElementRendererRegistry` and `ElementTypeRegistry` each
advertised themselves in dartdoc as an open-closed seam for consumers — "zero
core edits", "consumers add their own types" — and none of them is exported from
`lib/jet_print.dart`, nor accepted by any public entry point. The barrel exports
`JetReportFormat`, `ReportFormatException`, `UnknownElement` and
`UnknownScopeNode`; it exports no codec type, and `JetReportFormat` builds its
registry privately.

The mechanism works. `test/rendering/elements/persisted_extension_test.dart`
gives a `StarElement` its own `ElementCodec` and `ElementRenderer`, registers
both on an `ElementTypeRegistry`, round-trips it through `encodeDefinition` /
`decodeDefinition` and paints it, with no edit anywhere under `lib/src/`. It
reaches the registries through `package:jet_print/src/…` imports, which a
consumer cannot use. So the question is not whether the engine can carry a
third-party element. It is what a *public* registration API would owe, and to
whom.

What it would owe is the serialization contract. `AGENTS.md`'s hard rule is that
report JSON is versioned and lossless: a report written by a newer build must
round-trip through an older one, which is what `UnknownElement` and
`UnknownScopeNode` exist for, and a schema change needs a forward migration in
`domain/serialization/migration.dart`. A document naming a third-party element
type is exactly the case that rule covers — an older build, or a build without
that plugin installed, must still open it, still preserve it byte-equivalently,
and still migrate it when `kReportDefinitionSchemaVersion` moves. Today the set
of type keys is closed and first-party, so "unknown type" means "written by a
newer `jet_print`". Opening registration makes it mean "written by software we
have never seen", and the migration framework, the `UnknownElement` preservation
path and the designer's pass-through arms all acquire a second kind of input.

That is engine work, and under a semver promise it would have to be right before
the promise covers it, not after.

## Decision

`jet_print` `1.0.0` offers no public registration API for custom element types
or custom expression functions. The registries stay internal and pre-wired.

This is a product boundary, so it is stated as one rather than left to be
inferred from an absent export:

- the CHANGELOG's "that capability does not exist yet. Please open an issue."
  becomes a statement of scope — what the library does not do, and why — rather
  than a note apologising for an omission;
- `AGENTS.md` gains a line saying the element and expression registries are
  first-party and that adding a type is a change to this repository, alongside
  the existing pointer to `docs/recipes/add-element-type.md`;
- `packages/jet_print/README.md` gains the same line in the reader's direction:
  what a host can extend today — `JetDataSource`, `RenderOptions.fonts`,
  `RenderOptions.onElementPrint`, `PrintDialogPresenter` — and what it cannot.

That documentation work is P3. Until it lands, the boundary is real but
undocumented, which is the state this record exists to end.

## Consequences

**The 1.0 surface is as small as it can be.** Nothing about registration enters
the semver promise, so nothing about registration can break it.

**It is the fastest route to a freeze.** The alternative — design a public
registry, define what an unknown third-party type means to migration and to the
designer's tree-rebuilding switches, and prove it — is a substantial piece of
engine work that would sit directly on the critical path to `1.0.0`.

**The serialization contract stays entirely first-party.** Every `typeKey` that
appears in a document written by a `jet_print` build is one this repository
defined, which is what makes `UnknownElement` mean the single, testable thing it
means today.

**Opening the seam later is additive, not breaking.** This is the property that
makes the decision safe to take now. Exporting `ElementCodec`,
`ElementRendererRegistry` and an entry point that accepts a populated
`ElementTypeRegistry` adds names to the barrel and adds an optional parameter;
it does not change the meaning of any existing call. `1.0.0` therefore does not
foreclose the seam — it declines to promise one yet, which is a different thing,
and a `1.x` minor can open it the day the migration story is proven.

**It caps third-party adoption, and that is the cost.** A user who needs an
element type the library does not have has two options: fork, or upstream it and
wait. Both are worse than registering a class. Some fraction of potential users
will bounce off that and pick a library with a plugin model, and this decision
accepts losing them. What makes it acceptable is that the primary consumer is
first-party — for `apps/jet_print_playground`, and for the application this
library exists to serve, "upstream it" is a pull request to the same repository
by the same person, which is not a barrier at all. If that ever stops being
true, this record is the thing to supersede.

## What this does not decide

- **Not the internal registries' existence.** `ElementCodecRegistry`,
  `ElementRendererRegistry`, `ElementTypeRegistry` and `JetFunctionRegistry`
  stay, keep their last-write-wins semantics, and stay the mechanism
  `docs/recipes/add-element-type.md` and `add-expression-function.md` drive.
- **Not the eventual shape of a public seam.** Nothing here commits to
  exporting the current types as they stand; a future design is free to expose
  a narrower surface than the internal one.
- **Not the host seams that already exist.** `JetDataSource`,
  `RenderOptions.fonts`, `RenderOptions.onElementPrint` and
  `PrintDialogPresenter` are public extension points today, are in the 1.0
  surface, and are unaffected.
- **Not `UnknownElement`'s behaviour.** Forward compatibility with newer
  first-party builds is a separate, already-enforced contract
  (`test/domain/serialization/`, `docs/06-round-tripping.md`).
