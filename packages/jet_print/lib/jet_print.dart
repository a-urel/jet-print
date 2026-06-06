/// jet_print — a layered, theme-aware Flutter widget library for building
/// WYSIWYG report designers.
///
/// This is the library's **single public entry point**. Consumers import only:
///
/// ```dart
/// import 'package:jet_print/jet_print.dart';
/// ```
///
/// Everything under `lib/src/` is private implementation detail and is never
/// importable through a `package:jet_print/src/...` path. The intentional,
/// documented public surface is re-exported from here.
///
/// The public surface for this iteration: the version constant, a theme-aware
/// placeholder widget, the report-designer shell ([JetReportDesigner]), and the
/// library's own localization delegate ([JetPrintLocalizations]). See
/// `contracts/designer-layout-api.md` for the authoritative contract.
library;

export 'src/designer/jet_print_placeholder.dart' show JetPrintPlaceholder;
export 'src/designer/jet_report_designer.dart' show JetReportDesigner;
// The generated localizations class carries its own `delegate` and
// `supportedLocales` statics; consumers wire them into their app shell.
export 'src/designer/l10n/jet_print_localizations.dart'
    show JetPrintLocalizations;
export 'src/version.dart' show jetPrintVersion;
