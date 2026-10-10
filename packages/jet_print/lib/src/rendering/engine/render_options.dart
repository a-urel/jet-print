/// Per-render inputs for `JetReportEngine.renderDefinition`: host-supplied
/// parameter values plus the explicit formatting locale.
///
/// `dart:ui` is imported for the [Locale] **value type only** (it has a const
/// constructor and is what hosts already hold); no other `dart:ui` symbol may
/// be used here — the engine seam stays headless (see the layer-boundary
/// test's sanctioned-exception list).
library;

import 'dart:ui' show Locale;

import '../text/jet_font.dart';
import 'element_print_callback.dart';

/// The per-render inputs of a [JetReportEngine.renderDefinition] call, separate
/// from the definition: the values that may change on every render of the same design.
///
/// ```dart
/// const RenderOptions(
///   parameters: {'printedBy': 'A. Urel'}, // resolves $P{printedBy}
///   locale: Locale('de'),                 // number/date/currency formatting
/// )
/// ```
class RenderOptions {
  /// Creates render options; every field has a neutral default so
  /// `renderDefinition(definition, source)` works without any options.
  const RenderOptions({
    this.parameters = const <String, Object?>{},
    this.locale = const Locale('en'),
    this.knownFields,
    this.unresolvedFieldToken = '#ERROR',
    this.fonts = const <JetFontFamily>[],
    this.onElementPrint,
  });

  /// Host-supplied parameter values keyed by parameter name, resolved by
  /// `$P{name}` references.
  ///
  /// A parameter the template declares but the host does not supply falls back
  /// to its declared default; a declared parameter with neither a supplied
  /// value nor a default renders as empty and surfaces a diagnostic on
  /// `RenderedReport.diagnostics`.
  final Map<String, Object?> parameters;

  /// The explicit locale for number/date/currency formatting, and for the case
  /// mapping of `UPPER` and `LOWER`, during this render.
  ///
  /// Formatting and casing follow this locale only — never the app's UI locale
  /// and never the ambient `Intl.defaultLocale` — so the same render is
  /// deterministic wherever it runs. Defaults to the neutral `Locale('en')`.
  ///
  /// Date formatting for locales other than English requires the host to have
  /// initialized that locale's date symbols (e.g. `initializeDateFormatting()`
  /// from `package:intl/date_symbol_data_local.dart`) before rendering; number
  /// formatting needs no initialization.
  final Locale locale;

  /// The field names the active data source declares.
  ///
  /// A text binding that references a field outside this set renders
  /// [unresolvedFieldToken] instead of resolving empty, and records a warning.
  ///
  /// Left null, the set is derived from the data source when the source
  /// declares an explicit schema: `JetObjectDataSource` and
  /// `JetPagedDataSource` always do, and `JetInMemoryDataSource` and
  /// `JetJsonDataSource` do when constructed with `fields:`. The names of nested
  /// collection fields are included. A schema inferred from the rows, or a
  /// custom `JetDataSource`, derives nothing, and such a binding renders empty:
  /// inference cannot tell a misspelled field from an optional key that no row
  /// of this batch carries.
  ///
  /// Pass a set to override the derived one, for instance to accept a field a
  /// custom source supplies.
  final Set<String>? knownFields;

  /// The text rendered for a binding to a field absent from the known fields,
  /// whether passed as [knownFields] or derived from an explicit schema; unused
  /// when neither applies. Defaults to the literal
  /// `#ERROR`; a host with a `BuildContext` passes a localized value (e.g.
  /// `JetPrintLocalizations.of(context).errorUnresolvedToken`).
  final String unresolvedFieldToken;

  /// Host-contributed font families available to this render.
  ///
  /// The faces are the bytes the host hands in. The engine builds **one**
  /// `FontRegistry` (the bundled defaults, then these families
  /// last-registration-wins) and attaches it to the returned `RenderedReport`,
  /// so the preview, PDF/PNG export, and print paths all measure and paint from
  /// the identical bytes — WYSIWYG by construction. Register
  /// **before** rendering; the empty default reproduces today's behavior
  /// exactly.
  ///
  /// Pass the **same** `List<JetFontFamily>` here and to
  /// `JetReportDesigner.fonts`/`JetReportWorkspace.fonts` so the designer picker
  /// and the render chain offer and resolve the same families.
  final List<JetFontFamily> fonts;

  /// Host hook invoked once per element at emit time, on preview/export/print
  /// alike. Null (default) means no hook and byte-identical
  /// output to today. See [JetElementPrintCallback] for the contract.
  final JetElementPrintCallback? onElementPrint;
}
