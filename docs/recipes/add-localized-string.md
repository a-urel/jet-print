# Add a localized string

Three ARB edits, one generator run, and the reason the result is a code change rather than a text change.

`AGENTS.md` carries the localization rules under *Traps* — read them once before
your first ARB edit. Why `l10n.yaml` is configured the way it is, and what it
guarantees, is [page 10](../10-designer-seams.md). This page is the sequence.

## The sequence

1. **Template first.** Add the key to
   `lib/src/designer/l10n/jet_print_en.arb`, with its `@key` block carrying a
   `description`. That file is the template `l10n.yaml` names — `AGENTS.md`'s
   localization trap says why it is English — and the only one carrying `@`
   metadata.
2. **Then the other two.** Add the same key to `jet_print_de.arb` and
   `jet_print_tr.arb` — value only, no `@` block. Leaving a key out of one of
   them fails nothing ([page 10](../10-designer-seams.md) explains what closes
   the gap) and no test compares the three key sets, so compare them yourself:
   the files stay in step key for key.
3. **Generate.** From `packages/jet_print` — the directory holding `l10n.yaml` —
   run `flutter gen-l10n`. It prints a notice that `l10n.yaml` overrides command
   line arguments; that notice is the success case, not a warning.
4. **Read it back** as `JetPrintLocalizations.of(context).yourKey`. The getter is
   total, so there is no null branch to write.

## Your diff now contains Dart

`gen-l10n` writes `jet_print_localizations.dart` and one file per locale beside
the ARB sources, and all four are **tracked source**. So a change that felt like
editing text is a change to compiled code: `AGENTS.md`'s quality gate applies
whole — format, analyze, and the suite. Do not classify this as a docs-only
change.

Check the diff before you commit rather than after:

```bash
git status --short && git diff --stat
```

Expect exactly the three ARB files, the four generated Dart files, and whatever
callers you touched. Two readings of that output are worth acting on. If a
generated file carries a change `gen-l10n` did not produce, you typed into it —
`AGENTS.md`'s trap says what that costs; re-run and keep the generator's output.
And on a tree with no ARB edits at all, `flutter gen-l10n` must produce an empty
diff; if it does not, the committed generated files were already out of step
with the ARBs and that is a separate fix.

## Two things a test will not tell you

The `description` you wrote in step 1 is copied verbatim into the generated
getter's dartdoc. That makes it a claim about the string's purpose that ships in
the API surface, ages like any other comment, and fails nothing when it stops
being true. Write it as you would write a dartdoc.

Width is the other. If the string lands in a toolbar, a top bar or any fixed-width
chrome, overflow is locale-dependent — `AGENTS.md`'s localization trap names
which locale to suspect. Confirm by pumping the designer at that locale, not by
eyeballing the ARB. `test/designer/localization_de_test.dart` and its `_tr`
sibling are where such a check belongs; note that each non-English locale has its
own file for a reason spelled out there, so add to a file rather than merging
them.

## Verify

```bash
flutter test packages/jet_print/test/designer/
```

Then the full gate from the repository root. A new caption in existing chrome can
legitimately move a designer golden — [`update-goldens.md`](update-goldens.md).

## Next

[`update-goldens.md`](update-goldens.md) if one moved.
[Page 10](../10-designer-seams.md) for what `l10n.yaml`'s two pinned settings
actually guarantee, and how the library's localizations reach a host.
