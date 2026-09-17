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
// Collapsing the two into one IS achievable, and this test is the deliberate
// alternative to doing so — not a claim that it is impossible. Single-sourcing
// would run designer → expression, which the layer rules ALLOW and which this
// very catalog already does (it imports `aggregate/aggregate_functions.dart`
// to single-source the aggregate names). The expression seam would expose its
// name roster as a table, the catalog would comprehend over that roster and
// look UI metadata up by name, and drift would become a missing-key failure at
// build time — strictly stronger than a guard.
//
// The cost is what buys the guard instead: it inverts how the catalog is
// written, and it forces a group, a signature label and a caret offset onto
// every name the engine ever registers, including any the palette should not
// offer. That is a real trade, made knowingly. Note what is NOT a reason:
// `expression/` may not import `designer/`, but single-sourcing never needed
// that direction, and the registry never needed to hold a caret offset.
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
// Only the first is a defect. Equality is still the assertion, because the
// catalog's own dartdoc states the rule ("New engine function → add an entry
// here"), which makes the second direction a declared contract rather than an
// inference. But that is a weaker warrant than the one
// `built_in_element_registration_test.dart` has for ITS equality, where both
// directions are fatal (a throw on save / an Unknown placeholder). That test
// is the precedent for this one's SHAPE — a runtime key-set comparison — not
// for this one's choice of equality.
//
// Because the warrant is weaker, the escape hatch has to be real:
// `_deliberatelyUnpaletted` below is where an internal or deprecated engine
// function declares itself, so a legitimate exception is a one-line addition
// with a reason rather than a rewrite of the assertion.
//
// The AGGREGATE group is deliberately excluded from that comparison: `SUM`,
// `AVG` and `COUNT` are NOT registry functions. They are inline-aggregate
// sugar, expanded into hidden `ReportVariable`s by the aggregate synthesizer
// before evaluation, so they never reach the registry at all. (`MIN`/`MAX` sit
// on BOTH paths and so appear in the catalog twice, in different groups —
// which is why the comparison partitions by `group` and never by name.)
//
// The aggregate group gets its OWN equality instead, against the inverse of
// the `_aggregates` table (`aggregateNameFor` over `JetCalculation.values`).
// That direction matters and nothing else covers it: add a calculation to
// `_aggregates` and forget the catalog's seed list, and the palette silently
// fails to offer it — the existing `aggregate names are the inline-aggregate
// vocabulary` test hard-codes the five names, so it catches a DROPPED seed but
// never an ADDED calculation.
//
// It is deliberately NOT written as "every aggregate entry is a valid
// aggregate name". That restates the `aggregateCalculationFor(n) != null`
// filter the catalog already builds its aggregate entries behind, so it would
// pass by construction for every entry that filter can emit — a guard that
// cannot fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/template/expression_function_catalog.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_functions.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';

/// Engine functions deliberately kept OUT of the fx palette.
///
/// Empty today: every registered function is offered. To hide an internal or
/// deprecated engine function from the palette, add its name here WITH A
/// COMMENT saying why. That keeps the comparison below at full strength, and it
/// is why the equality assertion need not be weakened to a subset the first
/// time a legitimate exception appears.
const Set<String> _deliberatelyUnpaletted = <String>{};

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
      equals(_registeredNames().difference(_deliberatelyUnpaletted)),
      reason: 'expressionFunctionCatalog and registerBuiltInFunctions must '
          'cover the same names. A palette name missing from the registry is '
          'offered in the fx editor and then renders '
          'Unknown function "…" — a defect no parse check can see, because '
          'the parser holds no registry and accepts any well-formed '
          'identifier. An engine name missing from the palette evaluates '
          'correctly but is undiscoverable: if it is deliberately hidden, add '
          'it to _deliberatelyUnpaletted in this file with a comment saying '
          'why, rather than weakening this assertion.',
    );
  });

  test('the aggregate palette entries match the inline-aggregate vocabulary',
      () {
    final Set<String> vocabulary = <String>{
      for (final JetCalculation c in JetCalculation.values)
        if (aggregateNameFor(c) != null) aggregateNameFor(c)!,
    };
    expect(
      _aggregateCatalogNames(),
      equals(vocabulary),
      reason: 'The aggregate palette entries never reach the function '
          'registry: the synthesizer expands them into hidden ReportVariables '
          'before evaluation. They are pinned against the `_aggregates` table '
          'instead, in BOTH directions — a name the table does not know '
          'reaches the evaluator as a bare CallExpr and renders '
          'Unknown function "…", and a calculation the table gained but the '
          'catalog\'s seed list did not is simply never offered.',
    );
  });

  test('both name sets are non-empty (guards a vacuously passing comparison)',
      () {
    expect(_registeredNames(), isNotEmpty);
    expect(_scalarCatalogNames(), isNotEmpty);
    expect(_aggregateCatalogNames(), isNotEmpty);
  });

  test('no stale entry in the deliberately-unpaletted list', () {
    // Arms only once _deliberatelyUnpaletted is used; it iterates an empty set
    // today and is stated as such rather than dressed up as coverage. An
    // exception that outlives the function it excuses would silently shrink
    // the comparison above, which is the one way this file could rot back into
    // the overclaim it was written to remove.
    final Set<String> registered = _registeredNames();
    final Set<String> offered = _scalarCatalogNames();
    for (final String name in _deliberatelyUnpaletted) {
      expect(registered, contains(name),
          reason: '$name is excused from the palette but the engine no longer '
              'registers it — drop the exception.');
      expect(offered, isNot(contains(name)),
          reason: '$name is excused from the palette but IS offered in it — '
              'the exception contradicts the catalog; drop it.');
    }
  });
}
