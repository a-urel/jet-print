/// The coarse value-type taxonomy shared across the model (spec 005b).
///
/// A small, deliberately coarse tag used by data-field metadata
/// (`FieldDef.type`) and report-parameter declarations (`ReportParameter.type`)
/// to drive formatting and coercion — never a hard contract. It lives in the
/// innermost (`domain`) seam so both the `data` and `domain` layers can share
/// one enum without violating the inward-dependency rule. Pure Dart.
enum JetFieldType {
  /// Textual values (`String`).
  string,

  /// Whole numbers (`int`).
  integer,

  /// Fractional numbers (`double`), or a column mixing `int` and `double`.
  double,

  /// Boolean values (`bool`).
  boolean,

  /// Timestamps (`DateTime`).
  dateTime,

  /// Indeterminate — empty, all-null, or mixed/unsupported value types.
  unknown,
}
