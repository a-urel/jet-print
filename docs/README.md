# The wiki

Six pages follow one report from a definition with a single empty band to ink,
and each adds exactly one thing the page before it did without. Read in order
they are a narrative; read singly they are reference. Both uses are intended,
which is what the two lists below are for.

They teach mechanism. The rules themselves live in
[`../AGENTS.md`](../AGENTS.md), each named next to the test that enforces it —
start there if what you need is what must hold rather than why.

## The spine, in order

| # | Page | What it adds |
|---|---|---|
| 01 | [The smallest report](01-smallest-report.md) | a definition, a band, the one public door, and why the model is a tree |
| 02 | [Binding data](02-binding-data.md) | rows, `$F{}` expressions, master/detail, and the four places an aggregate folds |
| 03 | [Pagination](03-pagination.md) | heights become pages, lazily; furniture, page numbers, the break rules |
| 04 | [The frame](04-the-frame.md) | the keystone: one flat list of five primitives, which is why WYSIWYG holds |
| 05 | [Painting](05-painting.md) | that one frame as screen pixels, a PNG and a PDF, with nothing kept in sync by hand |
| 06 | [Round-tripping](06-round-tripping.md) | versioned JSON, forward migration, and what an older build does with a node it cannot name |

Page 04 is the one to read if you only read one. Everything before it exists to
produce a `PageFrame`; everything after it only draws one.

**Not written yet.** Four designer pages — `07-designer-loop.md` (the controller
and its command stack), `08-the-canvas.md` (design-time frame, hit-testing,
selection chrome), `09-the-panels.md` (outline, properties, inspectors) and
`10-designer-seams.md` (localization, value templates, and the designer's own
seams) — plus five recipes under `recipes/`: adding an element type, an expression
function or a localized string, regenerating goldens, and adding a playground
demo. They are later phases of this same wiki; until they land, the designer is
covered only by `AGENTS.md`'s layer table and trap list.

## If you came for one answer

| Question | Page |
|---|---|
| What is the minimum that renders? What is public and what is not? | 01 |
| Why is this binding empty, or showing `!ERR`? | 02 |
| My total is wrong, or counts the wrong rows | 02 |
| Why did that band land on the next page? Why is `$V{PAGE_NUMBER}` empty in it? | 03 |
| I want to draw something the library cannot draw yet | 04 |
| Why do the canvas, the preview and the PDF agree — and what would break that? | 04, 05 |
| Where do fonts, baselines and underlines come from? | 05 |
| What happens to a file this build does not fully understand? | 06 |
| I need a new `schemaVersion` | 06 |
| The designer, the command stack, the inspectors | not yet written — see `AGENTS.md` |

## The other two docs

- [`testing.md`](testing.md) — the test taxonomy, what each directory proves,
  golden discipline, the allowlist that lets library tests reach `src/`, and the
  per-platform CI legs.
- [`workflow.md`](workflow.md) — how a change moves from idea to merge, and where
  durable knowledge is supposed to end up.

Every claim on these pages is anchored to a file and a symbol, and every page
carries a **Run it** section naming the command that proves its claims. If a page
and the code disagree, the code is right and the page is a bug — fix it in the
same change.
