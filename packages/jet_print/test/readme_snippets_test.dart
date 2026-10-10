// Every Dart block in the package README is an excerpt of a file under
// `example/`, which the analyzer compiles and the example tests run. A README
// snippet once stopped compiling (a missing `text:`) without anything noticing;
// copying snippets from tested code is what keeps them working.
//
// The match is line by line with indentation and blank lines ignored, so a
// snippet may start mid-file and be indented differently, but every line it
// shows must appear, in order and contiguously, in one example file.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/workspace.dart';

List<String> _codeLines(String source) => source
    .split('\n')
    .map((String line) => line.trim())
    .where((String line) => line.isNotEmpty)
    .toList();

bool _containsRun(List<String> haystack, List<String> run) {
  for (int start = 0; start + run.length <= haystack.length; start++) {
    int i = 0;
    while (i < run.length && haystack[start + i] == run[i]) {
      i++;
    }
    if (i == run.length) return true;
  }
  return false;
}

void main() {
  final String package = '${findWorkspaceRoot().path}/packages/jet_print';
  final String readme = File('$package/README.md').readAsStringSync();
  final List<List<String>> snippets = RegExp(r'```dart\n([\s\S]*?)```')
      .allMatches(readme)
      .map((Match m) => _codeLines(m.group(1)!))
      .toList();
  final Map<String, List<String>> examples = <String, List<String>>{
    for (final FileSystemEntity f in Directory('$package/example').listSync())
      if (f is File && f.path.endsWith('.dart'))
        f.uri.pathSegments.last: _codeLines(f.readAsStringSync()),
  };

  test('the README shows Dart code and there are examples to check it', () {
    expect(snippets, isNotEmpty);
    expect(examples, isNotEmpty);
  });

  for (int i = 0; i < snippets.length; i++) {
    final List<String> snippet = snippets[i];
    test('README snippet ${i + 1} is copied from a tested example', () {
      expect(
        examples.values.any((List<String> e) => _containsRun(e, snippet)),
        isTrue,
        reason: 'README snippet starting "${snippet.first}" does not appear '
            'verbatim in any of ${examples.keys.join(', ')}. Copy README code '
            'from example/ (and edit it there) so it stays compiled and tested.',
      );
    });
  }
}
