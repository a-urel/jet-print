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
/// The public surface is intentionally minimal for this iteration: one
/// theme-aware placeholder widget and the library version constant. See
/// `contracts/public-api.md` for the authoritative contract.
library;

export 'src/designer/jet_print_placeholder.dart' show JetPrintPlaceholder;
export 'src/version.dart' show jetPrintVersion;
