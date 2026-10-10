#!/usr/bin/env bash
# Finishes P0 from your Mac. Everything here needs credentials that the
# sandboxed shell does not have — that is the only reason it is not done.
#
#   cd ~/Projects/oss/jet-print && bash /path/to/finish-p0.sh
#
set -euo pipefail

REPO="a-urel/jet-print"
cd "$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# 0. Clear the stale lock the sandboxed shell cannot delete.
#    Nothing is running; this file is leftover, and it blocks every commit.
# ---------------------------------------------------------------------------
rm -f .git/index.lock
find .git/objects -name 'tmp_obj_*' -delete

# ---------------------------------------------------------------------------
# 1. Check the work before it leaves the machine.
# ---------------------------------------------------------------------------
git log --oneline -1            # expect: docs(planning): land P0 ...
flutter analyze                 # the architecture tests guard doc figures
flutter test packages/jet_print/test/architecture

# ---------------------------------------------------------------------------
# 2. Push the branch and open the PR.
# ---------------------------------------------------------------------------
git push -u origin docs/p0-decisions
gh pr create --repo "$REPO" \
  --title "docs(planning): land P0 — roadmap on main, five decision records, P1 checklist" \
  --body "Closes P0. Restores the E1–E8 roadmap onto the tracked tree, adds \`docs/decisions/\` with records 0001–0005, and itemises P1 in \`docs/release-checklist.md\`. Records 0004 and 0005 rule on #32 and #35."

# ---------------------------------------------------------------------------
# 3. Milestones, with the phase exit criteria as their descriptions.
# ---------------------------------------------------------------------------
gh api "repos/$REPO/milestones" -f title="P1 — Publish 0.1.0" \
  -f description="Exit: flutter pub add jet_print works for a stranger."
gh api "repos/$REPO/milestones" -f title="P2 — Monépro embed pilot" \
  -f description="Exit: one real Monépro report rendered and exported from the published package, plus a written friction list."
gh api "repos/$REPO/milestones" -f title="P3 — Extensibility boundary and defect closure" \
  -f description="Exit: no open question that would force a breaking change after 1.0."
gh api "repos/$REPO/milestones" -f title="P4 — 1.0 freeze" \
  -f description="Exit: 1.0.0 on pub.dev with all six platforms declared and green."

# ---------------------------------------------------------------------------
# 4. Attach the two open issues to P3 and post the rulings.
#    The comment bodies are in docs/decisions/issue-replies.md — split there
#    under the '## Issue #32' and '## Issue #35' headings.
# ---------------------------------------------------------------------------
gh issue edit 32 --repo "$REPO" --milestone "P3 — Extensibility boundary and defect closure"
gh issue edit 35 --repo "$REPO" --milestone "P3 — Extensibility boundary and defect closure"

echo
echo "Now paste the two rulings from docs/decisions/issue-replies.md:"
echo "  gh issue comment 32 --repo $REPO --body-file <the #32 section>"
echo "  gh issue comment 35 --repo $REPO --body-file <the #35 section>"

# ---------------------------------------------------------------------------
# 5. The real pana baseline, which the sandbox could not produce.
#    Replace the estimates at the top of docs/release-checklist.md with these.
# ---------------------------------------------------------------------------
dart pub global activate pana
dart pub global run pana --json --no-warning packages/jet_print > pana.json
( cd packages/jet_print && flutter pub publish --dry-run 2>&1 | tee ../../dry-run.txt )
