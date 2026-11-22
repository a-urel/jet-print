# Contributing to jet-print

Thanks for your interest. Bug reports, questions and pull requests are all
welcome. Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Questions and ideas** go to
  [Discussions](https://github.com/a-urel/jet-print/discussions).
- **Bugs and feature requests** go to
  [Issues](https://github.com/a-urel/jet-print/issues/new/choose), using the
  templates.
- **Anything larger than a small fix** — a new feature, an API change, a new
  element type — please open an issue first, so the design can be agreed before
  you spend time on code. Some calls are already settled and recorded in
  [`docs/decisions/`](docs/decisions/); read the relevant one before proposing
  to undo it.

## Setting up

Flutter **3.44.0+** (Dart **^3.6.0**). From the repository root:

```bash
flutter pub get
```

[`README.md`](README.md) covers running the playground app.

## The rules

[`AGENTS.md`](AGENTS.md) is the contributor guide, for people and AI agents
alike: the hard rules, the test that enforces each one, the layer map and the
traps. Read it before your first change. In short:

- **Tests first.** Write the failing test, then the fix. A bug fix starts with a
  regression test that reproduces it.
- **The public API is what `lib/jet_print.dart` exports.** Nothing outside the
  library imports `lib/src/`.
- **Golden changes are deliberate.** If a golden moves, say in the pull request
  what moved and why. Goldens are canonical on CI's macOS runner only; don't
  commit goldens regenerated elsewhere
  ([`docs/recipes/update-goldens.md`](docs/recipes/update-goldens.md)).
- **User-visible changes** add an entry to
  [`packages/jet_print/CHANGELOG.md`](packages/jet_print/CHANGELOG.md), and
  public symbols carry dartdoc.
- **Don't commit a `pubspec.lock` rewritten by a newer Flutter.** CI resolves
  with the version pinned in `.github/workflows/ci.yml`.

## Before opening a pull request

Run the quality gate from the repository root. CI runs the same three checks
and fails on any of them:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/jet_print packages/jet_print_google_fonts apps/jet_print_playground
```

Name the member packages: `flutter test` at the workspace root alone tests
nothing.

Keep a pull request to one change, describe what it changes and why, and link
the issue it addresses.

## License

By contributing, you agree that your contributions are licensed under the
[Apache-2.0 license](LICENSE) that covers the project.
