// The Flutter agent rules exist once, and every copy of them matches.
//
// https://docs.flutter.dev/ai/get-started ships one rule file per rule from
// flutter/agent-plugins and asks each coding agent to hold it in its own
// place: Codex reads `.agent/rules/*.md`, Cursor reads `.cursor/rules/*.mdc`
// (same body, different front-matter), Copilot reads
// `.github/copilot-instructions.md`, and Claude Code reads `CLAUDE.md`. That
// is one rule and up to four files saying it, which is the shape this repo
// keeps finding rots: the copies agree on the day they are written and drift
// the first time someone refreshes one of them from upstream and not the
// others.
//
// So `.agent/rules/` is the canonical copy — the upstream `.md` verbatim —
// and this guard holds the rest to it. `CLAUDE.md` does not copy at all; it
// `@`-imports the canonical file, and the guard checks the import is there so
// the rule cannot silently fall out of Claude Code's context. The Cursor and
// Copilot files cannot import, so they carry the body, and the guard reads
// both bodies rather than trusting that they were pasted from the same place.
//
// Refreshing from upstream is therefore: replace `.agent/rules/<r>.md` and
// `.cursor/rules/<r>.mdc`, re-paste the body into the Copilot file, and let
// this test say whether anything was missed.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// The rule text with any leading YAML front-matter (`---` … `---`) removed
/// and line endings normalised, so two files that differ only in the
/// agent-specific header compare equal.
String _body(String text) {
  final List<String> lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    final int close = lines.indexWhere((String l) => l.trim() == '---', 1);
    if (close != -1) {
      return lines.sublist(close + 1).join('\n').trim();
    }
  }
  return text.trim();
}

/// The canonical rules: every `.md` file in `.agent/rules/`.
List<File> _canonicalRules(Directory root) {
  final Directory dir = Directory('${root.path}/.agent/rules');
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.md'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

String _stem(File f) =>
    f.path.replaceAll(r'\', '/').split('/').last.replaceAll('.md', '');

void main() {
  final Directory root = findWorkspaceRoot();
  final List<File> rules = _canonicalRules(root);

  test('there is at least one canonical rule (guards a vacuous loop)', () {
    expect(rules, isNotEmpty,
        reason: 'No `.md` files under .agent/rules/. Every other test here '
            'loops over that list, so an empty one would make them all pass '
            'while checking nothing.');
  });

  test('each canonical rule has a Cursor .mdc with the same body', () {
    for (final File rule in rules) {
      final File mdc = File('${root.path}/.cursor/rules/${_stem(rule)}.mdc');
      expect(mdc.existsSync(), isTrue,
          reason: '${_stem(rule)}: .agent/rules has it, .cursor/rules does '
              'not. Cursor cannot read the canonical file; copy the upstream '
              '.mdc beside it.');
      expect(
          _body(mdc.readAsStringSync()), equals(_body(rule.readAsStringSync())),
          reason: '${_stem(rule)}: the Cursor copy differs from the canonical '
              'rule below the front-matter. One of them was refreshed from '
              'upstream and the other was not.');
    }
  });

  test('each canonical rule body appears verbatim in the Copilot file', () {
    final File copilot = File('${root.path}/.github/copilot-instructions.md');
    expect(copilot.existsSync(), isTrue,
        reason: 'No .github/copilot-instructions.md. Copilot reads its rules '
            'from there and nowhere else.');
    final String text = copilot.readAsStringSync().replaceAll('\r\n', '\n');
    for (final File rule in rules) {
      expect(text, contains(_body(rule.readAsStringSync())),
          reason: '${_stem(rule)}: its body is not in '
              '.github/copilot-instructions.md verbatim. Copilot cannot '
              'import the canonical file; paste the body and keep it exact.');
    }
  });

  test('CLAUDE.md imports each canonical rule rather than copying it', () {
    final String claude = File('${root.path}/CLAUDE.md')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    for (final File rule in rules) {
      expect(claude, contains('@.agent/rules/${_stem(rule)}.md'),
          reason: '${_stem(rule)}: CLAUDE.md has no `@.agent/rules/'
              '${_stem(rule)}.md` import, so Claude Code never sees the rule. '
              'Import it; do not paste it — an import cannot drift.');
      // The import alone is not the invariant: a pasted body beside it would
      // keep the import and still be a copy that drifts. So the body must be
      // absent — checked by its first heading line, because a partially
      // pasted or already-drifted body would not match the whole text.
      final String heading = _body(rule.readAsStringSync()).split('\n').first;
      expect(claude, isNot(contains(heading)),
          reason: '${_stem(rule)}: CLAUDE.md contains the rule\'s body '
              '("$heading") as well as the import. That is a copy, and it '
              'will drift from .agent/rules/ the next time the rule is '
              'refreshed. Delete the pasted text; the import is enough.');
    }
  });
}
