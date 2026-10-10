# Decisions

Records of calls that were made once and should not have to be re-argued.

A decision record is not a plan and not a page of the wiki. It is the reasoning
behind one choice, written at the moment the choice was made, kept afterwards
whether or not it still looks right. [`../workflow.md`](../workflow.md), *Plans
and specs*, routes durable knowledge to five homes — the CHANGELOG, a doc
comment, `AGENTS.md` plus a test, the wiki, the trap list. Each of those answers
*what is true now*. None of them holds *why this was chosen, and what was
rejected*, which is the one thing that stops a later session quietly undoing the
call. Roughly 40,000 lines of plan documents were deleted from this repo for
drifting out of sync with the code; a record here avoids that failure by not
tracking the code at all.

## The convention

**Numbering.** `NNNN-kebab-title.md`, four digits, allocated in order and never
reused. A number identifies a record for the rest of the repo's life.

**Status.** Carried near the top of the record, before the Context, as one of
three values. An accepted record dates its acceptance; one that belongs to a
phase of the run to 1.0 may name the phase alongside it.

| Status | Meaning |
|---|---|
| `Proposed` | written, not yet decided — open for argument |
| `Accepted` | decided, and in force |
| `Superseded by NNNN` | no longer in force; the named record says what replaced it |

**A record is never edited after acceptance.** Not to correct it, not to soften
it, not to bring it up to date. If the decision changes, write a new record that
states the new decision and why the old one no longer holds, and set the old
one's status to `Superseded by NNNN` — that one line is the only permitted edit.
This is the whole value of the directory: an accepted record is evidence about
what was known and believed on its date, and an edited one is evidence about
nothing.

Two things follow from that, and both are deliberate:

- **Facts in a record are as of its date, and are not maintained.** A record
  that says the barrel exports 123 public names is stating a measurement taken
  the day it was written. It will go stale. It is not a bug when it does, and
  no test pins it. Live counts belong in `AGENTS.md` and the wiki, which are
  maintained; a record cites what it measured so the reasoning can be checked
  against the world as it then was.
- **A record that turned out wrong stays.** Superseding it says so in public.
  Deleting it loses the reason the mistake was reasonable at the time, which is
  the part worth having.

## The shape of a record

Title line, `Status`, then: **Context** — what was true that forced a choice;
**Decision** — the call, stated as a decision and not as a description;
**Consequences** — both directions, the cost stated as plainly as the benefit;
and, where a record is likely to be read as deciding more than it does, **What
this does not decide**. A record that lists only benefits has not finished
thinking. Roughly 60 to 120 lines.

Anchors are file and symbol, never `file:line`, for the reason
[`README.md`](../README.md), *Writing a page*, gives: a renamed symbol breaks
the anchor loudly, a moved line points silently at the wrong code.

## The records

| # | Record | Status |
|---|---|---|
| 0001 | [Publish `0.1.0` to pub.dev as a preview](0001-publish-0-1-0-as-a-preview.md) | Accepted 2026-09-21 |
| 0002 | [The extension seam stays closed for 1.0](0002-extension-seam-closed-for-1-0.md) | Accepted 2026-09-21 |
| 0003 | [Full mobile support is in 1.0 scope](0003-mobile-in-1-0-scope.md) | Accepted 2026-09-21 |
| 0004 | [What 1.0 must settle](0004-what-1-0-must-settle.md) | Accepted 2026-10-10 |

The directory itself is authoritative; this table is a convenience, and a record
that is present but unlisted is still in force.
