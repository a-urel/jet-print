// Web stand-in for release_notes_io.dart, so the release-notes test still
// compiles in the Chrome bundle, which cannot load `tool/`. That test is
// VM-only, so none of this runs; the signatures mirror
// tool/release_notes.dart.
Never _vmOnly() =>
    throw UnsupportedError('the release-notes script is tested on the VM only');

class ReleaseNotesException implements Exception {
  ReleaseNotesException(this.message);

  final String message;
}

class ReleaseNotes {
  const ReleaseNotes({
    required this.title,
    required this.body,
    required this.latest,
    required this.prerelease,
    required this.previousTag,
  });

  final String title;
  final String body;
  final bool latest;
  final bool prerelease;
  final String? previousTag;
}

ReleaseNotes buildReleaseNotes({
  required String tag,
  required String changelog,
  required String pubspec,
  required Iterable<String> tags,
}) =>
    _vmOnly();

String? changelogSection(String changelog, String version) => _vmOnly();

String installCommand(String version, {required String? previous}) => _vmOnly();

String unwrapMarkdown(String markdown) => _vmOnly();
