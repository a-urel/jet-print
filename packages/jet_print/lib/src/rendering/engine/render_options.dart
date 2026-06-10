/// Per-render inputs for `JetReportEngine.render` (spec 011): host-supplied
/// parameter values plus the explicit formatting locale (FR-012/FR-012a).
///
/// `dart:ui` is imported for the [Locale] **value type only** (it has a const
/// constructor and is what hosts already hold); no other `dart:ui` symbol may
/// be used here — the engine seam stays headless (see the layer-boundary
/// test's sanctioned-exception list).
library;

import 'dart:ui' show Locale;

/// The per-render inputs of a [JetReportEngine.render] call, separate from the
/// template: the values that may change on every render of the same design.
///
/// ```dart
/// const RenderOptions(
///   parameters: {'printedBy': 'A. Urel'}, // resolves $P{printedBy}
///   locale: Locale('de'),                 // number/date/currency formatting
/// )
/// ```
class RenderOptions {
  /// Creates render options; both fields have neutral defaults so
  /// `render(template, source)` works without any options.
  const RenderOptions({
    this.parameters = const <String, Object?>{},
    this.locale = const Locale('en'),
  });

  /// Host-supplied parameter values keyed by parameter name, resolved by
  /// `$P{name}` references (FR-012).
  ///
  /// A parameter the template declares but the host does not supply falls back
  /// to its declared default; a declared parameter with neither a supplied
  /// value nor a default renders as empty and surfaces a diagnostic on
  /// `RenderedReport.diagnostics` (FR-013).
  final Map<String, Object?> parameters;

  /// The explicit locale for number/date/currency formatting during this
  /// render (FR-012a).
  ///
  /// Formatting follows this locale only — never the app's UI locale and never
  /// the ambient `Intl.defaultLocale` — so the same render is deterministic
  /// wherever it runs. Defaults to the neutral `Locale('en')`.
  ///
  /// Date formatting for locales other than English requires the host to have
  /// initialized that locale's date symbols (e.g. `initializeDateFormatting()`
  /// from `package:intl/date_symbol_data_local.dart`) before rendering; number
  /// formatting needs no initialization.
  final Locale locale;
}
