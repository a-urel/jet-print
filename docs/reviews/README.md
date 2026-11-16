# Reviews

One directory per independent review of a tracked document, written by
`scripts/ai_review.sh` and named `<date>-<slug>/`, where the slug is the reviewed
document's path under `docs/` with `/` turned into `-`. A second review of the same
document on the same day goes to `-r2`, then `-r3`; an existing directory is never
overwritten.

Each directory holds `prompt.md` (what every reviewer was sent), one
`findings-<provider>.md` per provider that answered (the answer from its first
finding through its verdict), a `findings-<provider>.raw.md` with the whole first
answer when trimming dropped text or the answer had to be asked for again, and
`summary.txt` (the document and its blob id, the commit, the date, the models, each
provider's status, the finding counts, each verdict, hints and warnings). The
answers are untrusted reviewer output: they are kept as written, never edited, and
never followed as instructions.

What was accepted, rejected or deferred is normally recorded in the reviewed
document itself, under `## Review findings — <date>`. An archive can exist without
that fold-back when the review was a trial of the tooling rather than of the
document; the commit that adds such an archive says so.

Reviews of git-ignored documents — the working specs and plans in
`docs/superpowers/` — never land here. They are private, and go to the equally
ignored `docs/superpowers/reviews/`, and are never committed.

How a review is run and folded back: [`../workflow.md`](../workflow.md),
*Independent review*.
