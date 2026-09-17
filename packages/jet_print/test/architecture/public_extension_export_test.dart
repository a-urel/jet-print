// Architecture test: a public extension on an exported type is either exported
// or deliberately not — never accidentally not.
//
// **This test's value is not that it finds missing exports. It is that it
// forces every omission to be justified in writing.** It is expected to pass
// with an allowlist entry far more often than it is expected to fail: the
// allowlist below is the record of what is deliberately unexported, in the same
// way `encapsulation_test.dart`'s allowlist is the record of what is
// deliberately white-box. An entry without a reason erodes that record, so
// every entry carries one.
//
// The invariant: for each `extension <Name> on <Type>` under `lib/src/` where
// `<Name>` is public and `<Type>` reaches consumers through `jet_print.dart`,
// `<Name>` must appear in a `show` clause in the barrel — or in
// `_deliberatelyUnexported` with a reason. A public extension the barrel does
// not name is invisible through the package's only door, so its methods are
// uncallable by consumers even though the type they extend is public. That is
// sometimes exactly right (an internal helper) and sometimes a silent hole (the
// twelve `Ctrl*` command families ARE the controller's API; omitting one would
// make part of the controller uncallable). The two cases are indistinguishable
// from the source, which is why this test asks a human to say which it is
// rather than trying to decide.
//
// **Why this cannot be enforced structurally**, in the manner
// `barcode_dependency_isolation_test.dart` and
// `built_in_element_registration_test.dart` explain of their own invariants:
//
//   * Dart has no package-private. An extension must be public to be used from
//     a second library in the same package, so in this codebase `public` cannot
//     be read as "public API" — it reads as "used from more than one file".
//     There is no language-level signal to test against, only intent, and
//     intent has to be written down.
//   * This is a regex over declarations, not an analysis of the element model.
//     It sees `extension Foo on Bar` at the start of a line. It is therefore
//     evadable — an extension declared inside a `part` file whose declaration
//     is formatted unusually, a type reached through a typedef, or a receiver
//     written with a library prefix will slip past. It is a ratchet against
//     drift, not a proof.
//   * It judges "exported" by name, not by resolution: a `show`n name and a
//     declared name that merely coincide are treated as the same symbol.
//
// Consequence: a clean run means nothing new slipped in, not that the public
// surface is correct.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Extensions that are public **only** because Dart offers no package-private,
/// and that are deliberately absent from `jet_print.dart`.
///
/// Keyed by extension name, valued by the reason it stays internal. Adding an
/// entry is a decision to withhold something from consumers; make it explicitly
/// and say why, or export the extension instead.
const Map<String, String> _deliberatelyUnexported = <String, String>{
  // `ResizeHandleEdges` answers "which edges does dragging this handle move?"
  // for the three places that implement a resize: `resizeRect` and
  // `clampResizeToBand` in its own file, and `snapResize` in
  // `controller/snapping.dart`. That third site is the whole reason it is
  // public — `snapping.dart` is a separate library, and Dart has no
  // package-private.
  //
  // It is not API withheld by accident. `ResizeHandle` reaches consumers as a
  // PARAMETER type only — `CtrlResize.beginResize(String id, ResizeHandle
  // handle)` — so naming a handle is the entire requirement; nothing asks a
  // consumer to introspect one. The playground, the strict barrel-only
  // consumer, never mentions the enum, and no test calls the four getters.
  // Exporting them would publish an implementation helper and pin four names
  // as API for no caller.
  //
  // The twelve `Ctrl*` extensions are the opposite case, not a precedent: they
  // ARE the controller's API — `beginResize` itself lives on one — so omitting
  // them would make the controller partly uncallable. Omitting this one costs
  // a consumer nothing anyone has asked for.
  'ResizeHandleEdges':
      'internal geometry helper shared by the three resize sites; public only '
          'because snapping.dart is a separate library and Dart has no '
          'package-private. ResizeHandle is consumer-facing as a parameter '
          'type only, so these getters have no caller outside lib/.',
};

/// An `export` directive in the barrel, up to its terminating `;`, capturing the
/// URI and everything after it (the `show` clause, if any — which may span
/// several lines and, in the controller's case, contain `//` comments).
final RegExp _exportDirective = RegExp(
  r'''^export\s+['"]([^'"]+)['"]([^;]*);''',
  multiLine: true,
);

/// A top-level extension declaration: `extension Name on Type`, tolerating a
/// generic parameter list on the extension and generics/nullability on the
/// receiver.
final RegExp _extensionDecl = RegExp(
  r'^extension\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s+on\s+([A-Za-z_]\w*)',
  multiLine: true,
);

/// A public top-level type declaration, used to expand a wholesale (`show`-less)
/// export into the set of names it publishes.
final RegExp _typeDecl = RegExp(
  r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
  r'(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Za-z_]\w*)',
  multiLine: true,
);

/// Strips `//` line comments so names inside a `show` clause's commentary are
/// not mistaken for shown symbols.
String _stripLineComments(String s) => s.split('\n').map((String l) {
      final int i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');

List<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('every public extension on an exported type is exported or justified',
      () {
    final Directory root = findWorkspaceRoot();
    final Directory package = Directory('${root.path}/packages/jet_print');
    final File barrel = File('${package.path}/lib/jet_print.dart');
    final String barrelSource = _stripLineComments(barrel.readAsStringSync());

    // --- What the barrel publishes -----------------------------------------
    // Names listed in a `show` clause, plus — for a `show`-less export, which
    // publishes the whole file — every public type that file declares.
    final Set<String> exportedNames = <String>{};
    for (final RegExpMatch m in _exportDirective.allMatches(barrelSource)) {
      final String uri = m.group(1)!;
      final String tail = m.group(2)!;
      final int showAt = tail.indexOf('show');
      if (showAt == -1) {
        final File exported = File('${package.path}/lib/$uri');
        if (!exported.existsSync()) continue;
        final String src = exported.readAsStringSync();
        for (final RegExpMatch d in _typeDecl.allMatches(src)) {
          exportedNames.add(d.group(1)!);
        }
        for (final RegExpMatch d in _extensionDecl.allMatches(src)) {
          exportedNames.add(d.group(1)!);
        }
        continue;
      }
      for (final String name in tail.substring(showAt + 4).split(',')) {
        final String trimmed = name.trim();
        if (trimmed.isNotEmpty) exportedNames.add(trimmed);
      }
    }

    expect(
      exportedNames,
      contains('ReportDefinition'),
      reason: 'the barrel parse found nothing recognisable — the scan would '
          'be vacuous',
    );

    // --- Public extensions on those types ----------------------------------
    final List<String> offenders = <String>[];
    final Set<String> seen = <String>{};
    for (final File f in _dartFiles(Directory('${package.path}/lib/src'))) {
      final String src = f.readAsStringSync();
      for (final RegExpMatch m in _extensionDecl.allMatches(src)) {
        final String name = m.group(1)!;
        final String receiver = m.group(2)!;
        if (name.startsWith('_')) continue;
        if (!exportedNames.contains(receiver)) continue;
        if (exportedNames.contains(name)) continue;
        if (_deliberatelyUnexported.containsKey(name)) continue;
        seen.add(name);
        offenders.add(
          '$name on $receiver (${f.path.split('/packages/jet_print/').last})',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These public extensions sit on a type the barrel exports, but '
          'the barrel does not name them, so consumers cannot call their '
          'members. Either add each to the relevant `show` clause in '
          'jet_print.dart, or record it in `_deliberatelyUnexported` with the '
          'reason it stays internal: $offenders',
    );
  });

  test('every allowlist entry still names a real public extension', () {
    final Directory lib = Directory(
      '${findWorkspaceRoot().path}/packages/jet_print/lib/src',
    );

    final Set<String> declared = <String>{};
    for (final File f in _dartFiles(lib)) {
      for (final RegExpMatch m in _extensionDecl.allMatches(
        f.readAsStringSync(),
      )) {
        declared.add(m.group(1)!);
      }
    }

    final List<String> stale = _deliberatelyUnexported.keys
        .where((String name) => !declared.contains(name))
        .toList();
    expect(
      stale,
      isEmpty,
      reason: 'allowlist entries for extensions that no longer exist — a stale '
          'entry silently widens the exemption if the name is ever reused: '
          '$stale',
    );

    final List<String> unexplained = _deliberatelyUnexported.entries
        .where((MapEntry<String, String> e) => e.value.trim().length < 20)
        .map((MapEntry<String, String> e) => e.key)
        .toList();
    expect(
      unexplained,
      isEmpty,
      reason: 'allowlist entries without a real reason — the list is only the '
          'record of deliberate omissions if every entry says why: $unexplained',
    );
  });
}
