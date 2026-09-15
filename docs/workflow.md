# Workflow

How a change moves from idea to merge. Written tool-agnostically; Claude Code
users get the same phases as named skills in [`../CLAUDE.md`](../CLAUDE.md).

## The phases

### 1. Understand before building

Before writing code for anything new — a feature, a component, a behavior change
— establish what is actually wanted. Ask the questions whose answers would change
what you build, one at a time. Explore the existing code rather than assuming the
shape of it.

Then present the design and **stop**. Get an explicit yes before implementing.
This holds for small changes too; what scales with size is the length of the
design, never the approval.

Scale the ceremony to the work:

- A feasibility question ("can we…") wants a cheap probe and an answer, not code
  you keep.
- A bounded change to a flow that already exists wants a few questions and a
  short design in chat.
- A new subsystem, or anything that changes interfaces others depend on, wants
  the full treatment: approaches with trade-offs, a sectioned design, then a
  written plan.

When in doubt between two, take the heavier one. Complexity discovered mid-task
upgrades the path; nothing downgrades it.

### 2. Work on a branch

Never commit feature work directly to `main`. Branch first. For work that needs
isolation from an in-progress workspace, use a git worktree.

### 3. Test first

Write the failing test. Run it. Watch it fail *for the reason you expect* — a
test that fails because of a typo in the test is not a red. Then implement until
it passes, then refactor.

A bug fix starts the same way: a regression test that reproduces the bug before
any fix exists. If you cannot reproduce it in a test, you do not yet understand
it.

### 4. Debug systematically

When something breaks, resist the first plausible fix. Find the actual mechanism:
read the error, form a hypothesis that predicts something you can check, check
it. A fix that makes a symptom disappear without explaining it usually moved the
bug rather than removing it.

### 5. Verify before claiming

Run the quality gate and read the output before saying anything is done, fixed
or passing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/jet_print apps/jet_print_playground
```

Evidence before assertions. "Tests pass" is a claim about output you have
actually seen.

### 6. Update what the change touches

In the same change, not later:

- `packages/jet_print/CHANGELOG.md` for anything user-visible.
- Dartdoc on any public symbol added or changed.
- `AGENTS.md` or `docs/` if the change invalidates guidance there.
- Goldens, deliberately, with the visual change named.

### 7. Review, then integrate

Get the change reviewed before merging. A reviewer's job includes checking the
rules in `AGENTS.md` — especially test-first and the single paint path, which are
the two that degrade quietly.

Receiving review feedback is a technical exercise, not a social one. Verify a
suggestion before implementing it; disagree with reasons when it is wrong. Neither
blind agreement nor reflexive defense.

## Plans and specs

Working documents — designs, implementation plans, task notes — belong in
`docs/superpowers/`, which is **git-ignored**. They are scaffolding for the work
in progress, not repository history.

This is deliberate. Roughly 40,000 lines of per-feature plan documents accumulated
here and were deleted wholesale, because nobody reread them and they drifted out
of sync with the code they described. Knowledge that should outlive a branch goes
where it will be found:

| Knowledge | Home |
|---|---|
| What changed, for users | `CHANGELOG.md` |
| Why this code is shaped this way | A doc comment next to it |
| A rule everyone must follow | `AGENTS.md`, plus a test enforcing it |
| How a subsystem fits together | `docs/architecture.md` |
| A trap that cost someone a day | The trap list in `AGENTS.md` |

A rule written only in prose decays silently. Where you can, land it as a test
and let `AGENTS.md` point at the test — then the rule fails loudly when it stops
being true.
