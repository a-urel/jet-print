// Architecture test: nothing caches on a frame primitive.
//
// `domain/value_equality.dart` warns that the mixin's `==`/`hashCode` walk
// `List` props element-wise, so a `Map` or `Set` keyed on such a value pays
// O(content) on *every* probe, not just on a hit. Both decoded-image caches
// learned it the expensive way — `CanvasPainter`'s in PR #27 and
// `PdfPainter._decoded` in #31 — each decoding one texture per ROW for a
// repeated image, because `ImagePrimitive.bytes` was hashed on every lookup AND
// `bounds`/`elementId` are in `props` too, so a repeated image never hit.
//
// Both are fixed, so this guard is green on arrival. It exists for the next
// cache, and for the shape `value_equality.dart` names as still unguarded:
// nothing caches on a text primitive today, and anything that starts to pays
// the same probe over `TextRunPrimitive.lines`.
//
// WHY PRIMITIVES AND NOT EVERY `ValueEquality` TYPE.
//
// The dartdoc's rule reads as blanket — "when caching, key on something O(1)
// (an identity, an id) rather than on the value itself" — and the first version
// of this test enforced it that way. It failed immediately, on six call sites,
// all of them correct:
//
//   * `crosstab_planner.dart` keys `_leaves` on `CrosstabAxisNode` — but through
//     `Map<CrosstabAxisNode, _ColumnLeaf>.identity()`, so `==` is never called.
//     The field's own dartdoc says why identity is required: sibling nodes under
//     different parents (`2025/Q1`, `2026/Q1`) are equal by value and must not
//     collide. A regex sees the type argument, not the constructor.
//   * `crosstab_matrix.dart` and `crosstab_aggregator.dart` key on
//     `CrosstabCellKey`, whose `List<String>` props are axis PATHS — bounded by
//     nesting depth, a handful of short strings — and whose value semantics are
//     exactly what a cell address wants. Nothing like hashing an image.
//
// So the blanket rule is good advice and a bad invariant: this codebase holds
// it for primitives and deliberately breaks it elsewhere. The harm needs an
// unbounded `List` prop (`bytes`, `lines`) or props that vary per use
// (`bounds`, `elementId`) — both of which are properties of `FramePrimitive`,
// not of the mixin. Widening the scan to the mixin produced six false positives
// and zero findings; a guard that cries wolf on arrival is one the next person
// mutes.
//
// WHAT THIS PROVES, AND WHAT IT DOES NOT.
//
// It is a regex over declaration text, in the idiom of the other tests in this
// directory, and it is evadable the same ways they are:
//
//   * a `typedef` for the key type hides it;
//   * a type parameter (`Map<T, V>` in a generic class) is invisible;
//   * `var cache = <SomePrimitive, int>{}` inferred from a literal is not
//     matched;
//   * it closes the type set over `extends` only — a primitive reached through
//     `implements`, or a cache keyed on a type that merely CONTAINS one, is
//     missed;
//   * as the crosstab case shows, it cannot tell a value map from an identity
//     map, so a `Map<ImagePrimitive, X>.identity()` would be a false positive.
//     None exists today; if one appears, allowlist it with that reason.
//
// So it enforces the rule, it does not fully prevent breaking it — the same
// trade-off `ElementTypeRegistry.register` documents for its covariant `E`. Its
// value is that an ordinary `Map<ImagePrimitive, X>` cannot land silently.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Primitive types allowed to be a `Map`/`Set` key despite the rule.
///
/// Empty on purpose. An entry here is a deliberate exception and must say why —
/// the `encapsulation_test.dart` convention, where the list IS the record of
/// what was decided rather than what was forgotten. An unexplained entry erodes
/// the guard faster than no guard.
const Set<String> _allowedKeyTypes = <String>{};

final RegExp _mixesIn = RegExp(
  r'^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+'
  r'(\w+)[^{]*\bwith\b[^{]*\bValueEquality\b',
  multiLine: true,
);

final RegExp _extendsClause = RegExp(
  r'^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+'
  r'(\w+)(?:<[^>]*>)?\s+extends\s+(\w+)',
  multiLine: true,
);

/// Every source file under the library's `lib/`, by path.
Map<String, String> _libSources() {
  final Directory root = findWorkspaceRoot();
  return <String, String>{
    for (final File f in Directory('${root.path}/packages/jet_print/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart')))
      f.path: f.readAsStringSync(),
  };
}

/// The types this guard bans as `Map`/`Set` keys: `FramePrimitive` plus every
/// class reaching it through `extends`.
///
/// The closure is load-bearing, not decorative. `FramePrimitive` declares the
/// mixin and its five subclasses inherit it WITHOUT restating it, so a
/// seed-only scan would miss `TextRunPrimitive` and `ImagePrimitive` — the two
/// `value_equality.dart` names as the ones that bite. Both tests below run
/// against this function's output, so disabling the closure fails the second
/// test rather than quietly shrinking what the first one checks.
Set<String> _bannedKeyTypes(Map<String, String> sources) {
  final Set<String> types = <String>{
    for (final String s in sources.values)
      for (final Match m in _mixesIn.allMatches(s))
        if (m.group(1) == 'FramePrimitive') m.group(1)!,
  };
  final Map<String, String> parentOf = <String, String>{
    for (final String s in sources.values)
      for (final Match m in _extendsClause.allMatches(s))
        m.group(1)!: m.group(2)!,
  };
  bool grew = true;
  while (grew) {
    grew = false;
    parentOf.forEach((String child, String parent) {
      if (types.contains(parent) && types.add(child)) grew = true;
    });
  }
  return types.difference(_allowedKeyTypes);
}

void main() {
  test('no Map or Set in lib/ is keyed on a frame primitive', () {
    final Map<String, String> sources = _libSources();
    final Set<String> banned = _bannedKeyTypes(sources);
    final RegExp keyed = RegExp(
      '(?:Map|Set)<\\s*(${banned.map(RegExp.escape).join('|')})\\s*[,>]',
    );

    final List<String> offenders = <String>[];
    sources.forEach((String path, String source) {
      for (final Match m in keyed.allMatches(source)) {
        final int line =
            '\n'.allMatches(source.substring(0, m.start)).length + 1;
        final String rel = path.split('/packages/jet_print/').last;
        offenders.add('$rel:$line keys on ${m.group(1)}');
      }
    });

    expect(
      offenders,
      isEmpty,
      reason: 'A Map/Set keyed on a frame primitive pays O(content) on every '
          'probe over its List props and may never hit — see '
          'domain/value_equality.dart. Key on an identity instead (the byte '
          'buffer, an id). If the key is genuinely safe (an identity map, say), '
          'add it to _allowedKeyTypes WITH that reason.\n'
          '${offenders.join('\n')}',
    );
  });

  test('the ban set includes types that only INHERIT the mixin', () {
    // Guards the guard, and asserts on the produced set rather than on the
    // regexes feeding it: an earlier version checked only that the patterns
    // matched text, which stayed green when the `extends` closure was disabled
    // — so the first test silently stopped covering the two types that matter.
    final Set<String> banned = _bannedKeyTypes(_libSources());
    expect(banned, contains('FramePrimitive'),
        reason: 'the sealed base must seed the set');
    expect(banned, containsAll(<String>['TextRunPrimitive', 'ImagePrimitive']),
        reason: 'these inherit ValueEquality without restating it; if they are '
            'absent the `extends` closure has regressed and the first test is '
            'checking less than it appears to');
  });
}
