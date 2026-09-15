# CLAUDE.md

The project guidance for every agent lives in `AGENTS.md`. Read it first —
it is imported here:

@AGENTS.md

Everything below is Claude Code specific and adds to, never overrides, the rules
in `AGENTS.md`.

## Use the superpowers skills

This project drives development through the `superpowers` plugin. Invoke the
skill for the phase you are in rather than improvising the process:

| Phase | Skill |
|---|---|
| Any new feature, component, or behavior change — **before** planning | `superpowers:brainstorming` |
| Turning an approved design into an implementation plan | `superpowers:writing-plans` |
| Executing a written plan | `superpowers:executing-plans`, or `superpowers:subagent-driven-development` for independent tasks |
| Writing any feature or bugfix | `superpowers:test-driven-development` |
| Any bug, test failure, or surprise | `superpowers:systematic-debugging` |
| Before claiming anything is done, fixed, or passing | `superpowers:verification-before-completion` |
| Before merging | `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch` |
| Feature work needing an isolated workspace | `superpowers:using-git-worktrees` |

`docs/workflow.md` describes the same phases in tool-agnostic prose, for agents
that don't have these skills.

## Where plans live

`brainstorming` and `writing-plans` write to `docs/superpowers/`. That directory
is **git-ignored on purpose**: plans are working scaffolding, not repo history.
Durable knowledge belongs in `CHANGELOG.md`, in doc comments next to the code, or
in `AGENTS.md` / `docs/` — not in a plan file nobody will reread.

## Subagents

Subagents truncate mid-task and sometimes report success they did not achieve.
After delegating, verify the committed git state yourself rather than trusting
the report.
