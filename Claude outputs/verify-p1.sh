#!/usr/bin/env bash
# Verifies the P1 work. Nothing in those five commits has been compiled,
# analysed, formatted or tested — no Dart or Flutter toolchain was reachable
# from the session that wrote them. This script is where that happens.
#
#   cd ~/Projects/oss/jet-print && bash /path/to/verify-p1.sh
#
# Run it before finish-p0.sh pushes anything.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# 0. Clear the locks git left behind and could not remove.
#    The sandboxed shell cannot delete files in your folders, so every git
#    operation that took a lock left it there. Nothing is running.
# ---------------------------------------------------------------------------
rm -f .git/index.lock .git/HEAD.lock .git/objects/maintenance.lock
rm -f .git/refs/heads/docs/p0-decisions.lock
find .git/objects -name 'tmp_obj_*' -delete
git status --short          # expect: only .claude/ and "Claude outputs/" untracked
git log --oneline 2236ed4~1..HEAD

# ---------------------------------------------------------------------------
# 1. Does the workspace still resolve? The example is a new member with a
#    path dependency onto another member — the single most likely failure.
#    If it fails: replace `jet_print: {path: ../}` in
#    packages/jet_print/example/pubspec.yaml with a bare `jet_print:`.
# ---------------------------------------------------------------------------
flutter pub get || echo "!! workspace resolution failed — see note above"

# ---------------------------------------------------------------------------
# 2. The zero-warning gate, now including example/lib.
# ---------------------------------------------------------------------------
flutter analyze

# ---------------------------------------------------------------------------
# 3. THE ONE THAT MATTERS. Analysing from inside the package directory, under
#    the new package-local config, is something nobody has ever done. Expect
#    real diagnostics, including in the generated l10n output.
# ---------------------------------------------------------------------------
( cd packages/jet_print && flutter analyze . )

# ---------------------------------------------------------------------------
# 4. Formatting. Hand-wrapped code is the likeliest thing to fail here.
#    If it does: `dart format .` and amend.
# ---------------------------------------------------------------------------
dart format --output=none --set-exit-if-changed .

# ---------------------------------------------------------------------------
# 5. Tests. The architecture guards are the ones this work touched.
# ---------------------------------------------------------------------------
( cd packages/jet_print && flutter test \
    test/architecture/analysis_options_parity_test.dart \
    test/architecture/guard_table_completeness_test.dart \
    test/architecture/public_extension_export_test.dart \
    test/public_api_test.dart )
( cd packages/jet_print && flutter test )

# ---------------------------------------------------------------------------
# 6. Prove the example is an app, not just a file that analyses.
# ---------------------------------------------------------------------------
( cd packages/jet_print/example && flutter create . && flutter build macos --debug )

# ---------------------------------------------------------------------------
# 7. The two remaining P1 items, which need pub.dev.
# ---------------------------------------------------------------------------
flutter pub outdated          # expect shadcn_ui ^0.54.0 to have moved
flutter pub get               # refreshes the stale intl entry in pubspec.lock

# ---------------------------------------------------------------------------
# 8. The number this was all for. Replace the estimates at the top of
#    docs/release-checklist.md with what these actually say.
# ---------------------------------------------------------------------------
dart pub global activate pana
dart pub global run pana --json --no-warning packages/jet_print > pana.json
( cd packages/jet_print && flutter pub publish --dry-run 2>&1 | tee ../../dry-run.txt )

echo
echo "If all of the above is green, P1's file work is verified and the"
echo "remaining step is the publish itself."
