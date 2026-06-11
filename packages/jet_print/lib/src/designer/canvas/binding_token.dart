/// Design-time token labels for data-bound elements (US2 / FR-010; 013).
library;

import '../template/value_template_compiler.dart';

/// The visible token shown at design time for a binding [expression] (tokens
/// only — values are never resolved here). It is the same projection the value
/// field shows, so canvas and Properties panel never diverge (013 SC-002): a
/// plain field reference `$F{name}` collapses to a clean `[name]`; a template
/// binding shows as `{ … }`; an out-of-grammar (legacy) expression is shown
/// verbatim inside braces. ASCII brackets keep the token glyph-safe in goldens.
String fieldTokenLabel(String expression) => reverseCompile(expression).text;
