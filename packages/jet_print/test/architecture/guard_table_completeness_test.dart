// The `AGENTS.md` guard table lists every file in `test/architecture/`.
//
// That table is the roster of whole-repo invariants, and it loads into every
// agent session through the `CLAUDE.md` import. A guard missing from it is a
// guard the next author does not know exists — they hit its failure with no
// idea what it protects, or they write the same guard again.
//
// It went stale four times in one day. Each time the fix was to re-copy the
// directory into the table by hand, and each time it was correct when written
// and wrong within the hour: several branches land guards concurrently, and a
// hand-maintained mirror of a directory listing has nothing holding it to the
// directory. One of those repairs shipped in the very change whose stated
// purpose was to make the table accurate.
//
// The table also carried a COUNT ("holds four whole-repo guards") that
// disagreed with its own rows. Removing the count stopped the count and the
// list contradicting each other; it could not stop the list and the DIRECTORY
// contradicting each other, because nothing read the directory. This does.
//
// Both directions are checked, because they rot differently. A file with no row
// is an invisible guard. A row with no file outlives the guard it describes and
// sends the next author looking for a test that is not there — and that one is
// invisible to any check that only walks the directory.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// The line that opens the guard table. The rows are read from directly below
/// it, rather than from anywhere in the file, so an unrelated table elsewhere
/// in `AGENTS.md` can never be mistaken for this one.
const String _tableMarker = '`test/architecture` holds';

/// The `*_test.dart` files that actually live in `test/architecture/`.
Set<String> _guardFiles(Directory root) =>
    Directory('${root.path}/packages/jet_print/test/architecture')
        .listSync()
        .whereType<File>()
        .map((File f) => f.path.replaceAll(r'\', '/').split('/').last)
        .where((String name) => name.endsWith('_test.dart'))
        .toSet();

/// The guard filenames named in the first column of the `AGENTS.md` table.
Set<String> _tabledGuards(Directory root) {
  final List<String> lines = File('${root.path}/AGENTS.md').readAsLinesSync();
  final int marker = lines.indexWhere((String l) => l.contains(_tableMarker));
  expect(marker, isNot(-1),
      reason:
          'AGENTS.md no longer contains "$_tableMarker". If the table moved '
          'or was reworded, update _tableMarker — do not delete this test: a '
          'marker that matches nothing would make it pass vacuously.');
  final RegExp row = RegExp(r'^\|\s*`([A-Za-z0-9_]+_test\.dart)`\s*\|');
  final Set<String> named = <String>{};
  for (final String line in lines.skip(marker)) {
    final RegExpMatch? m = row.firstMatch(line);
    if (m != null) {
      named.add(m.group(1)!);
    } else if (named.isNotEmpty && !line.startsWith('|')) {
      break; // past the end of the table
    }
  }
  return named;
}

void main() {
  final Directory root = findWorkspaceRoot();

  test('every guard in test/architecture has a row in the AGENTS.md table', () {
    expect(
      _guardFiles(root),
      equals(_tabledGuards(root)),
      reason: 'The AGENTS.md guard table and test/architecture/ must name the '
          'same files. A guard with no row is invisible to the next author, '
          'who loads that table every session and will not find the test any '
          'other way. A row with no guard outlives the test it describes. Add '
          'the row (one line, the invariant in the same voice as its '
          'neighbours) or drop it.',
    );
  });

  test('the table was actually found (guards a vacuous comparison)', () {
    expect(_tabledGuards(root), isNotEmpty,
        reason: 'No rows parsed from the AGENTS.md table — the marker matched '
            'but the row format did not, so the comparison above would be '
            'asserting one empty set against another.');
    expect(_guardFiles(root), isNotEmpty);
  });
}
