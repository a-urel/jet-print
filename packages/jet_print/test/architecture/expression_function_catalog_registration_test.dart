// The fx palette and the engine's function table may not drift apart.
//
// The library names its callable functions twice, on two independent paths:
//
//   * `registerBuiltInFunctions` (expression) — the evaluator's name→function
//     table. A call node whose name is absent here evaluates to
//     `Unknown function "…"`.
//   * `expressionFunctionCatalog` (designer) — the fx editor's palette
//     metadata: group, signature label, insert snippet, caret offset. The
//     engine's registry carries no UI data, so this list is hand-written.
//
// The lists cannot be collapsed into one: `expression/` may not import
// `designer/` (see layer_boundaries_test.dart), so the registry can never
// carry the palette metadata; and the registry's entries are closures, which
// cannot supply a signature label or a caret offset. So they stay two
// hand-written lists, and this test is what keeps them honest.
//
// This is a RUNTIME key-set comparison, not a source scan, for the same reason
// `built_in_element_registration_test.dart` is: a registration written any
// other way (a cascade, a loop, a helper) would fool a text scan, and the
// catalog's aggregate entries are *computed* at list-build time.
//
// Why EQUALITY and not merely subset. The two directions fail very
// differently:
//
//   * catalog ∖ registry — an offered name the engine cannot evaluate. The
//     author picks it out of the palette and the field renders
//     `Unknown function "…"`. Fatal, user-visible, and invisible to CI.
//   * registry ∖ catalog — an engine function missing from the palette. It
//     still evaluates; it is merely undiscoverable.
//
// Only the first is a defect, but equality is still the right assertion: the
// catalog's own dartdoc states the rule ("New engine function → add an entry
// here"), so the second direction is a declared contract rather than an
// inference. A function deliberately kept out of the palette should have to
// say so — the way `encapsulation_test.dart` makes each white-box test declare
// itself — instead of drifting in silently.
//
// The AGGREGATE group is deliberately excluded from that comparison: `SUM`,
// `AVG` and `COUNT` are NOT registry functions. They are inline-aggregate
// sugar, expanded into hidden `ReportVariable`s by the aggregate synthesizer
// before evaluation, so they never reach the registry at all. (`MIN`/`MAX` sit
// on BOTH paths and so appear in the catalog twice, in different groups —
// which is why the comparison partitions by `group` and never by name.)
//
// A second, group-agnostic test is the net under that exclusion: every entry,
// whatever its group, must resolve on ONE of the two paths. It is what catches
// a bogus name filed under `aggregate`, where the scalar comparison cannot
// look. Note it is deliberately NOT written as "aggregate entries are valid
// aggregate names": the catalog BUILDS its aggregate entries behind an
// `aggregateCalculationFor(n) != null` filter, so that assertion would restate
// a production tautology and could not fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/template/expression_function_catalog.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_functions.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';

/// The names the evaluator can actually dispatch, built the way the fill and
/// layout paths build theirs.
Set<String> _registeredNames() {
  final JetFunctionRegistry registry = JetFunctionRegistry();
  registerBuiltInFunctions(registry);
  return registry.registeredNames.toSet();
}

/// The palette names that must resolve through the evaluator's registry —
/// every group except `aggregate`.
Set<String> _scalarCatalogNames() => expressionFunctionCatalog
    .where(
        (ExpressionFunction f) => f.group != ExpressionFunctionGroup.aggregate)
    .map((ExpressionFunction f) => f.name)
    .toSet();

/// The palette names that resolve through the inline-aggregate synthesizer.
Set<String> _aggregateCatalogNames() => expressionFunctionCatalog
    .where(
        (ExpressionFunction f) => f.group == ExpressionFunctionGroup.aggregate)
    .map((ExpressionFunction f) => f.name)
    .toSet();

void main() {
  test('every scalar fx palette entry names a function the engine registers',
      () {
    expect(
      _scalarCatalogNames(),
      equals(_registeredNames()),
      reason: 'expressionFunctionCatalog and registerBuiltInFunctions must '
          'cover the same names. A palette name missing from the registry is '
          'offered in the fx editor and then renders '
          'Unknown function "…" — a defect no parse check can see, because '
          'the parser holds no registry and accepts any well-formed '
          'identifier. An engine name missing from the palette evaluates '
          'correctly but is undiscoverable; if it is deliberately hidden, say '
          'so here rather than letting it drift.',
    );
  });

  test('every fx palette entry resolves on one of the engine\'s two paths', () {
    final JetFunctionRegistry registry = JetFunctionRegistry();
    registerBuiltInFunctions(registry);
    final List<String> unresolvable = <String>[
      for (final ExpressionFunction f in expressionFunctionCatalog)
        if (registry.lookup(f.name) == null &&
            aggregateCalculationFor(f.name) == null)
          '${f.name} (${f.group.name})',
    ];
    expect(
      unresolvable,
      isEmpty,
      reason: 'Every offered name must be dispatchable: either the evaluator '
          'registry holds it, or the aggregate synthesizer expands it into a '
          'hidden ReportVariable before evaluation. A name on neither path '
          'reaches the evaluator as a bare CallExpr and renders '
          'Unknown function "…". This is the group-agnostic net under the '
          'per-group assertions: it catches a bogus entry filed under '
          '`aggregate`, which the scalar comparison above deliberately skips. '
          'Unresolvable:',
    );
  });

  test('both name sets are non-empty (guards a vacuously passing comparison)',
      () {
    expect(_registeredNames(), isNotEmpty);
    expect(_scalarCatalogNames(), isNotEmpty);
    expect(_aggregateCatalogNames(), isNotEmpty);
  });
}
