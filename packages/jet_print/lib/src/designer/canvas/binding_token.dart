/// Design-time token labels for data-bound elements (US2 / FR-010).
library;

/// A simple field reference: `$F{name}` and nothing else.
final RegExp _fieldRef = RegExp(r'^\$F\{([^}]*)\}$');

/// The visible token shown at design time for a binding [expression] (tokens
/// only — values are never resolved here). A plain field reference `$F{name}`
/// collapses to a clean `[name]`; any richer expression is shown verbatim inside
/// the same brackets so it reads, unambiguously, as a placeholder rather than
/// literal text. ASCII brackets keep the token glyph-safe in golden rendering.
String fieldTokenLabel(String expression) {
  final Match? m = _fieldRef.firstMatch(expression);
  final String inner = m != null ? m.group(1)! : expression;
  return '[$inner]';
}
