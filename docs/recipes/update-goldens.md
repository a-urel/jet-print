# Regenerate goldens

What to do when a golden fails, in an order that keeps `--update-goldens` from erasing the evidence.

The rule — a golden moves deliberately or not at all — is in
[`../../AGENTS.md`](../../AGENTS.md); the discipline behind it, including the two
causes that recur here, is [`../testing.md`](../testing.md) under *Goldens*. Read
that section before you decide a shift is noise. This page is the mechanics, and
all of it assumes the canonical host `AGENTS.md`'s golden trap names.

## The sequence

1. **Get the list, from the test run.** Not from `git status`:

   ```bash
   flutter test --tags golden packages/jet_print
   ```

   Every failure names its golden. That is the set that moved — write it down
   before you touch anything.

2. **Look at the images**, but identify them from step 1's list, not from the
   directory. A comparison writes its PNGs beside the test:

   ```bash
   find packages/jet_print/test -type d -name failures
   ```

   That directory is untracked and nothing ever cleans it, so what is in it can
   outlive the run that wrote it — it is not a record of *this* run. Match
   filenames and timestamps against step 1, then open `*_masterImage.png` and
   `*_testImage.png` side by side, with `*_isolatedDiff.png` for where they
   part.

3. **Name what moved, and why, in a sentence you would defend in review.** If
   you cannot, you have found a bug, not a golden. Check `../testing.md`'s two
   recurring explanations before assuming your change is the cause.

4. **Regenerate only the files from step 1**, one test file at a time:

   ```bash
   flutter test --update-goldens packages/jet_print/test/goldens/rendered_invoice_test.dart
   ```

   Never run `--update-goldens` across a whole package. It rewrites the PNG of
   **every** golden the run touches, passing ones included — re-encoding alone
   changes the bytes, and the comparator tolerates a small pixel difference
   besides (`test/support/golden_config_io.dart`) — so a broad update yields a
   diff in which a real move and a byte-level no-op look identical.

5. **Read the diff back against that list.**

   ```bash
   git diff --stat packages/jet_print/test
   ```

   It must name exactly the goldens you expected. Restore anything else with
   `git checkout --` before going on.

6. **Re-run without the flag**, both the file you regenerated and the whole
   tagged set, and confirm green.

7. **Put step 3's sentence in the commit body**, naming each golden file you
   regenerated, as `AGENTS.md`'s golden rule requires.

## Verify

```bash
flutter test --tags golden packages/jet_print
```

Then the full gate from the repository root, in the order `AGENTS.md` gives it —
whose golden trap also explains why a locally green golden suite is no evidence
that CI ever reached one.

## Next

[`add-localized-string.md`](add-localized-string.md) and
[`add-playground-demo.md`](add-playground-demo.md) are the changes most likely to
have sent you here; [page 05](../05-painting.md) is what the goldens compare.
