# The wiki

Ten pages and five recipes. The pages follow one report from a definition with a
single empty band to ink, and then into the designer that edits it; each adds
exactly one thing the page before it did without. The recipes are sequences for
changes people actually make. Read in order the pages are a narrative; read
singly they are reference. Both uses are intended, which is what the tables
below are for.

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
| 07 | [The designer loop](07-designer-loop.md) | one mutation point, a snapshot per step, and why every edit is a command object |
| 08 | [The canvas](08-the-canvas.md) | the design-time frame is the render path; hit-testing, and chrome that never enters the picture |
| 09 | [The panels](09-the-panels.md) | the outline, how the properties panel picks an inspector, and one path from a callback to an undoable step |
| 10 | [Designer seams](10-designer-seams.md) | inherited scopes, lookups, value templates, localization, and what the barrel charges |

Page 04 is the one to read if you only read one. Everything before it exists to
produce a `PageFrame`; everything after it either draws one, or edits the
definition that produces the next one.

## The recipes

A recipe is a sequence, plus whatever analysis that sequence needs and nothing
more. Each cites the page that says why it has that shape, and `AGENTS.md` for
the rules it crosses.

| Doing this | Recipe |
|---|---|
| Adding an element type | [`recipes/add-element-type.md`](recipes/add-element-type.md) |
| Adding an expression function | [`recipes/add-expression-function.md`](recipes/add-expression-function.md) |
| Adding a localized string | [`recipes/add-localized-string.md`](recipes/add-localized-string.md) |
| Adding a playground demo | [`recipes/add-playground-demo.md`](recipes/add-playground-demo.md) |
| A golden failed | [`recipes/update-goldens.md`](recipes/update-goldens.md) |

What no page covers: the printing seam (`lib/src/print/`, `JetReportPrinter`),
and how a `PivotGrid` is planned (`rendering/crosstab/`) — the designer side of a
crosstab is page 09, the planner has no page. For those two, `AGENTS.md`'s layer
table and traps are the whole of the written guidance.

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
| My edit is not undoable, or undo takes back too much | 07 |
| A gesture hit the wrong thing, or selection chrome is in the exported page | 08 |
| Where is this property authored, and how does an editor reach the controller? | 09 |
| An extension's methods vanished from the public API | 10 |
| A string shows in English under a German locale | 10 |

## The other two docs

- [`testing.md`](testing.md) — the test taxonomy, what each directory proves,
  golden discipline, the allowlist that lets library tests reach `src/`, and the
  per-platform CI legs.
- [`workflow.md`](workflow.md) — how a change moves from idea to merge, and where
  durable knowledge is supposed to end up.

## Writing a page

These conventions are the format, not a house style. They are what makes a page
checkable, and a page that keeps their surface while losing their intent is the
failure this section exists to prevent — "match the existing pages" preserves
only what is visible in the output.

**Page anatomy — six elements.** A narrative page:

1. Opens with a concrete claim, not a preamble. The first paragraph says what is
   true, not what the page will cover.
2. Puts the smallest working thing first — a command and what it prints, not a
   block of code to copy.
3. Introduces one concept at a time.
4. Shows mechanism from real code: five to ten lines, quoted rather than
   paraphrased, anchored by file and symbol.
5. Carries a section saying **why it is like this, and which alternative was
   rejected** — the content, under whatever heading the page needs. A page
   without one documents the shape and loses the reason, and the reason is the
   part that stops the next person undoing it.
6. Puts traps in place rather than in a list at the end, each naming the test
   that enforces it.

It ends with **Run it** and **Next**. A recipe is the smaller form: the same
opening claim, then **The sequence** as numbered steps, **Verify**, **Next**.

**Length.** A narrative page is 120–200 lines, a recipe 60–80 — a budget you
work to, which is the one kind of line number that belongs here. The ceiling is
the working part: a page at 200 lines cannot absorb a new paragraph, only trade
for one, and that trade is where the editing happens. A peer session once
spliced a paragraph into a page already at the ceiling because nothing outside a
git-ignored plan file said the ceiling existed.

**Anchors are file and symbol, never `file:line`.** A renamed symbol breaks the
anchor loudly, because grep finds nothing; a moved line silently points at the
wrong code. The same rot is why no page *describes* code by a line count: it is a
number that goes wrong without saying so.

The same asymmetry governs how you check a claim. **A pattern tells you where to
look, never what is there.** In a repo that hard-wraps prose, a grep for a
multi-word phrase has a hole exactly as wide as the line width — "stops there"
finds nothing when it wrapped as "stops / there", and the sweep hunting the
`_groupSection` dartdoc missed it because it reads "three pagination / flags".
Search for the rarest single token, then read the region. An empty result is the
one outcome that feels like an answer and never is.

**Every "run this" runs against code CI already runs.** The command itself is
usually narrower than CI's — a single directory rather than the whole suite — but
the tests behind it must be tests CI executes. Code invented for a page is proven
by nothing and decays unobserved.

**One fact, one layer.** `AGENTS.md` carries the contract — what must hold, and
the test that enforces it. `docs/` carries the mechanism: why the seam exists.
`docs/recipes/` carries the procedure: the sequence. A lower layer may **cite** a
higher one by name and location; it may never **restate** it in its own words.

Two failure modes of that last rule, both learned writing these pages:

- **The pull to restate is strongest when you are fixing an omission**, because
  the omission feels like it needs compensating for. And a restatement is not
  only a copy that may drift later — it can be born wrong:
  `recipes/add-element-type.md` reworded page 06's registration trap and
  inverted it (`122b829`, M1), one sentence after citing that page correctly.
- **A mirrored pair is an alarm, not a verdict.** When the same claim appears
  twice, what it fires is a question — is the other one wrong, or merely
  *similar*? The same words can be false in one place and true in another. Page
  03 says the three `GroupLevel` pagination flags reach into the layouter loop,
  which is textually the claim corrected across six comment sites in `88e6072`,
  and is true here: those comments were about what the UI surfaces, the page is
  about the model. Reading the shape as the verdict manufactures errors while
  removing them, in the places a reviewer is least likely to look — and the
  author of the sweep is the worst-placed person to catch it.

If a page and the code disagree, the code is right and the page is a bug — fix
it in the same change.
