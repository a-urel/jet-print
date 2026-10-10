// Architecture test: a public member of an exported type does not expose a
// type the barrel withholds — or says why it does.
//
// The invariant: for each type or extension that `jet_print.dart` exports, a
// public field, getter or method declared on it has no type from `lib/src/`
// that the barrel does not export, unless `_deliberatelyExposed` names the
// member with a reason. Such a member is a hole in the public surface. A
// consumer cannot name the type, yet can call every member of it through the
// field, so those members freeze with the field at 1.0 without anyone having
// decided to publish them. `RenderedReport.fonts`, of the internal
// `FontRegistry`, was exactly that until #102
// ([`docs/api-friction.md`](../../../../docs/api-friction.md), entry 20).
//
// Like `public_extension_export_test.dart`, this is a regex over source lines,
// not an analysis of the element model, so it is a ratchet against drift, not a
// proof:
//
//   * It reads members at a class body's two-space indent only, and attributes
//     them to the nearest top-level `class`, `mixin`, `enum` or `extension`
//     above. Unusual formatting slips past; `dart format` makes that rare.
//   * It checks declared types, not parameters: a public constructor or method
//     PARAMETER of an unexported type is not caught. Naming such a type in a
//     signature only lets a consumer pass on a value it got from elsewhere, and
//     the members it returns are what this test is for.
//   * It judges "exported" by name, as the extension guard does.
//
// A clean run means nothing new slipped in, not that the surface is correct.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Public members of exported types that deliberately expose an unexported
/// type, keyed `Owner.member`, valued by the reason.
///
/// An entry is a decision that a consumer may reach the type's members through
/// this one door without the type being exported. Make it explicitly, or hide
/// the member, or export the type.
const Map<String, String> _deliberatelyExposed = <String, String>{
  // `PageFrame` is the backend-agnostic display list every painter and exporter
  // reads, and the playground's rendered-example tests inspect
  // `pageAt(i).frame.primitives` to check what a report printed. Whether a
  // consumer may read it — export `PageFrame` and the primitives, or hide the
  // field — is undecided: api-friction entry 22, before 1.0 under
  // decisions/0004, because either way the surface changes.
  'RenderedPage.frame':
      'undecided: api-friction entry 22 (#105) — export the frame IR or hide '
          'the field, before 1.0',
  // `SnapGuide` is what the selection overlay draws while a move or resize
  // snaps. The controller is public because hosts drive it, but the guides are
  // the canvas's own business; whether they stay readable is the same open
  // question as `frame`, recorded with it.
  'JetReportDesignerController.activeGuides':
      'undecided: api-friction entry 22 (#105) — export SnapGuide or hide the '
          'getter, before 1.0',
};

/// An `export` directive in the barrel, up to its terminating `;`, capturing
/// the URI and everything after it (the `show` clause, if any).
final RegExp _exportDirective = RegExp(
  r'''^export\s+['"]([^'"]+)['"]([^;]*);''',
  multiLine: true,
);

/// A top-level public type declaration.
final RegExp _typeDecl = RegExp(
  r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
  r'(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Za-z_]\w*)',
  multiLine: true,
);

/// A top-level declaration that opens a body whose members this test reads.
final RegExp _ownerDecl = RegExp(
  r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
  r'(?:class|enum|mixin|extension\s+type|extension)\s+([A-Za-z_]\w*)',
);

/// A member at a class body's indent: optional modifiers, a type starting with
/// an uppercase identifier (generics and nullability allowed), an optional
/// `get`, a public name, then what ends a field, getter or method head.
final RegExp _memberDecl = RegExp(
  r'^  (?:(?:static|final|late|const|external|covariant)\s+)*'
  r'([A-Z][\w.]*(?:<[^;=(){}]*>)?\??)\s+(?:get\s+)?([a-z]\w*)\s*(?:;|=|\{|\()',
);

final RegExp _identifier = RegExp(r'[A-Z]\w*');

String _stripLineComments(String s) => s.split('\n').map((String l) {
      final int i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');

List<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

/// Every `Owner.member` on an exported owner whose declared type names an
/// unexported `lib/src/` type, mapped to the offending type names.
Map<String, Set<String>> _exposures() {
  final Directory package =
      Directory('${findWorkspaceRoot().path}/packages/jet_print');
  final String barrel = _stripLineComments(
      File('${package.path}/lib/jet_print.dart').readAsStringSync());

  final Set<String> exported = <String>{};
  for (final RegExpMatch m in _exportDirective.allMatches(barrel)) {
    final String tail = m.group(2)!;
    final int showAt = tail.indexOf('show');
    if (showAt == -1) {
      final File f = File('${package.path}/lib/${m.group(1)!}');
      if (!f.existsSync()) continue;
      final String src = f.readAsStringSync();
      for (final RegExpMatch d in _typeDecl.allMatches(src)) {
        exported.add(d.group(1)!);
      }
      continue;
    }
    for (final String name in tail.substring(showAt + 4).split(',')) {
      if (name.trim().isNotEmpty) exported.add(name.trim());
    }
  }
  expect(exported, contains('RenderedReport'),
      reason: 'the barrel parse found nothing recognisable — the scan would '
          'be vacuous');

  final List<File> files = _dartFiles(Directory('${package.path}/lib/src'));
  final Set<String> unexported = <String>{};
  for (final File f in files) {
    for (final RegExpMatch d in _typeDecl.allMatches(f.readAsStringSync())) {
      final String name = d.group(1)!;
      if (!name.startsWith('_') && !exported.contains(name)) {
        unexported.add(name);
      }
    }
  }

  final Map<String, Set<String>> found = <String, Set<String>>{};
  for (final File f in files) {
    String? owner;
    for (final String line in f.readAsLinesSync()) {
      final RegExpMatch? o = _ownerDecl.firstMatch(line);
      if (o != null) {
        owner = o.group(1);
        continue;
      }
      if (line.startsWith('}')) {
        owner = null;
        continue;
      }
      if (owner == null || !exported.contains(owner)) continue;
      final RegExpMatch? m = _memberDecl.firstMatch(line);
      if (m == null) continue;
      final Set<String> hidden = _identifier
          .allMatches(m.group(1)!)
          .map((RegExpMatch t) => t.group(0)!)
          .where(unexported.contains)
          .toSet();
      if (hidden.isEmpty) continue;
      found
          .putIfAbsent('$owner.${m.group(2)!}', () => <String>{})
          .addAll(hidden);
    }
  }
  return found;
}

void main() {
  test('no exported type exposes an unexported type through a public member',
      () {
    final Map<String, Set<String>> exposures = _exposures();
    final List<String> offenders = <String>[
      for (final MapEntry<String, Set<String>> e in exposures.entries)
        if (!_deliberatelyExposed.containsKey(e.key))
          '${e.key} (${e.value.join(', ')})',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'These public members of exported types have a type the barrel '
          'does not export, so a consumer can call its members without the '
          'type being public. Hide the member, export the type, or record it '
          'in `_deliberatelyExposed` with the reason: $offenders',
    );
  });

  test('every allowlist entry still names a real exposure', () {
    final Set<String> exposed = _exposures().keys.toSet();
    final List<String> stale = <String>[
      for (final String key in _deliberatelyExposed.keys)
        if (!exposed.contains(key)) key,
    ];
    expect(
      stale,
      isEmpty,
      reason: 'These `_deliberatelyExposed` entries no longer match a member '
          'that exposes an unexported type; remove them: $stale',
    );
  });
}
