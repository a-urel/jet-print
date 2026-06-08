/// The reserved page-scoped variable names (spec 007b §2) — the single authority.
/// Their *values* are resolvable only by Layout (008), which imports this set;
/// 007b rejects their use in the bands and expressions it processes.
library;

/// Variable names that denote page-scoped values (resolved at layout time).
const Set<String> kPageScopedVariables = <String>{'PAGE_NUMBER', 'PAGE_COUNT'};
