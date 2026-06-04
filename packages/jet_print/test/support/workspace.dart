import 'dart:io';

/// Locates the jet_print workspace root by walking up from the current working
/// directory until it finds the directory that contains both
/// `packages/jet_print` and `apps/jet_print_tester`.
///
/// `flutter test` may run with the current directory set to either the package
/// root or the workspace root depending on how it is invoked, so tests that
/// scan the source tree must not assume one or the other. Deriving every path
/// from this anchor keeps those scans correct — and, crucially, non-vacuous —
/// regardless of the working directory.
Directory findWorkspaceRoot() {
  Directory dir = Directory.current.absolute;
  while (true) {
    final bool hasLibrary =
        Directory('${dir.path}/packages/jet_print').existsSync();
    final bool hasTester =
        Directory('${dir.path}/apps/jet_print_tester').existsSync();
    if (hasLibrary && hasTester) return dir;

    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate the jet_print workspace root starting from '
        '${Directory.current.path}. Expected an ancestor containing both '
        'packages/jet_print and apps/jet_print_tester.',
      );
    }
    dir = parent;
  }
}
