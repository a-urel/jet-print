/// One-pass variable & aggregate calculator (spec 005b).
library;

import '../../data/data_row.dart';
import '../../domain/report_group.dart';
import '../../domain/report_variable.dart';
import '../eval_context.dart';
import '../expression.dart';
import '../function_registry.dart';
import '../value.dart';
import 'variable_accumulator.dart';

/// Computes report variables row-by-row, folding aggregates and resetting
/// group-scoped variables on group breaks.
///
/// Usage (the Fill stage drives this): call [start], then [advance] once per
/// data row in order; read [valueOf]/[values] after each advance to feed
/// element-expression evaluation, and [brokenGroups] to drive group footers
/// (008). Variables fold in declaration order; a variable's expression sees the
/// current [values] (updated for earlier-declared variables this row) via
/// `$V{}`.
class VariableCalculator {
  /// Creates a calculator over [variables] and [groups] (outermost first),
  /// compiling each expression once with [functions].
  VariableCalculator({
    required List<ReportVariable> variables,
    required List<ReportGroup> groups,
    required JetFunctionRegistry functions,
  })  : _variables = List<ReportVariable>.unmodifiable(variables),
        _groups = List<ReportGroup>.unmodifiable(groups),
        _functions = functions,
        _varExprs = <Expression>[
          for (final ReportVariable v in variables)
            Expression.parse(v.expression),
        ],
        _accumulators = <VariableAccumulator>[
          for (final ReportVariable v in variables)
            VariableAccumulator(v.calculation),
        ],
        _groupExprs = <Expression>[
          for (final ReportGroup g in groups) Expression.parse(g.expression),
        ];

  final List<ReportVariable> _variables;
  final List<ReportGroup> _groups;
  final JetFunctionRegistry _functions;
  final List<Expression> _varExprs;
  final List<VariableAccumulator> _accumulators;
  final List<Expression> _groupExprs;

  final Map<String, JetValue> _values = <String, JetValue>{};
  List<JetValue>? _prevKeys;
  Set<String> _brokenGroups = const <String>{};

  /// (Re)initializes all accumulators and clears group state.
  void start() {
    for (final VariableAccumulator a in _accumulators) {
      a.reset();
    }
    _values.clear();
    for (final ReportVariable v in _variables) {
      _values[v.name] = const JetNull();
    }
    _prevKeys = null;
    _brokenGroups = const <String>{};
  }

  /// Processes one [row] (with optional [params]), updating all variable values.
  ///
  /// Must be called after [start] (and once per row, in order); calling it
  /// without a prior [start] yields undefined results.
  void advance(DataRow row,
      {Map<String, Object?> params = const <String, Object?>{}}) {
    EvalContext ctx() => RowEvalContext(
          row: row,
          params: params,
          variables: _values,
          functions: _functions,
        );

    // 1. Evaluate this row's group keys.
    final List<JetValue> keys = <JetValue>[
      for (final Expression e in _groupExprs) e.evaluate(ctx()),
    ];

    // 2. Detect the outermost broken group; all inner groups break too.
    _brokenGroups = <String>{};
    final List<JetValue>? prev = _prevKeys;
    if (prev != null) {
      for (int i = 0; i < _groups.length; i++) {
        if (keys[i] != prev[i]) {
          for (int j = i; j < _groups.length; j++) {
            _brokenGroups.add(_groups[j].name);
          }
          break;
        }
      }
    }

    // 3. Reset group-scoped variables whose group broke (before folding).
    if (_brokenGroups.isNotEmpty) {
      for (int k = 0; k < _variables.length; k++) {
        final ReportVariable v = _variables[k];
        if (v.resetScope == VariableResetScope.group &&
            v.resetGroup != null &&
            _brokenGroups.contains(v.resetGroup)) {
          _accumulators[k].reset();
          _values[v.name] = _accumulators[k].value;
        }
      }
    }

    // 4. Fold each variable in declaration order; $V{} sees updated _values.
    for (int k = 0; k < _variables.length; k++) {
      final JetValue input = _varExprs[k].evaluate(ctx());
      _accumulators[k].fold(input);
      _values[_variables[k].name] = _accumulators[k].value;
    }

    _prevKeys = keys;
  }

  /// The current value of [variableName] (or [JetNull] if undeclared).
  JetValue valueOf(String variableName) =>
      _values[variableName] ?? const JetNull();

  /// All current variable values (for building an element-evaluation context).
  Map<String, JetValue> get values =>
      Map<String, JetValue>.unmodifiable(_values);

  /// The group names that broke on the most recent [advance] (empty on the
  /// first row). Drives group footers/headers in the layout stage (008).
  /// Returned as an unmodifiable view (the internal set is replaced each
  /// [advance]), mirroring [values]' defensive copy.
  Set<String> get brokenGroups => Set<String>.unmodifiable(_brokenGroups);
}
