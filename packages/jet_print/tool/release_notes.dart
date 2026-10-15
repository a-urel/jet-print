// Writes the GitHub Release notes for a `jet_print-vX.Y.Z` tag, from the
// `## X.Y.Z` section of CHANGELOG.md. `.github/workflows/release.yml` runs it
// when such a tag is pushed; run it from the package root to see the notes a
// tag would get:
//
//   dart run tool/release_notes.dart jet_print-v1.1.0 notes.md
//
// It writes the notes to the file and prints `title=`, `latest=` and
// `prerelease=` lines, which the workflow appends to `$GITHUB_OUTPUT`. It
// fails, and the release is not created, when the CHANGELOG has no section for
// the tag's version or `pubspec.yaml` declares a different version.
//
// The notes keep the format the hand-written releases set, pinned by
// `test/tool/release_notes_test.dart`: the section's intro, the install
// command, links to pub.dev and the CHANGELOG at the tag, the section's
// subsections promoted one heading level, and a comparison with the previous
// tag. The CHANGELOG is hard-wrapped, and a release body renders every single
// newline as a line break, so wrapped lines are joined first.
import 'dart:convert';
import 'dart:io';

/// What every `jet_print` release tag starts with; the version follows it.
const String tagPrefix = 'jet_print-v';

const String _repository = 'https://github.com/a-urel/jet-print';

/// Why the notes for a tag could not be written.
class ReleaseNotesException implements Exception {
  /// Creates the exception with the [message] the job prints.
  ReleaseNotesException(this.message);

  /// What is wrong, in a sentence that names what to fix.
  final String message;

  @override
  String toString() => message;
}

/// The release a tag gets.
class ReleaseNotes {
  /// Creates the notes; [buildReleaseNotes] is the way to get one.
  const ReleaseNotes({
    required this.title,
    required this.body,
    required this.latest,
    required this.prerelease,
    required this.previousTag,
  });

  /// The release title, `jet_print X.Y.Z`.
  final String title;

  /// The release body, in Markdown.
  final String body;

  /// Whether this is the highest released version, and so GitHub's Latest.
  final bool latest;

  /// Whether the version carries a pre-release suffix such as `-dev.1`.
  final bool prerelease;

  /// The tag the body compares with, or null for the first release.
  final String? previousTag;
}

/// Builds the release for [tag] from the package's [changelog] and [pubspec]
/// text, given every release [tags] in the repository.
///
/// The previous tag is the highest one below [tag], skipping pre-releases
/// unless [tag] is one. Throws a [ReleaseNotesException] when [tag] names no
/// version, [pubspec] declares another version, or [changelog] has no section
/// for it.
ReleaseNotes buildReleaseNotes({
  required String tag,
  required String changelog,
  required String pubspec,
  required Iterable<String> tags,
}) {
  final _Version? current = _versionOfTag(tag);
  if (current == null) {
    throw ReleaseNotesException(
      '"$tag" is not a release tag: expected $tagPrefix<semver>, '
      'such as ${tagPrefix}1.2.0.',
    );
  }
  final String version = current.text;

  final String? declared = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (declared != version) {
    throw ReleaseNotesException(
      'pubspec.yaml declares version ${declared ?? '(none)'}, '
      'but the tag is $tag. Bump the pubspec before tagging.',
    );
  }

  final String? section = changelogSection(changelog, version);
  if (section == null) {
    throw ReleaseNotesException(
      'CHANGELOG.md has no "## $version" section. '
      'Add one before tagging.',
    );
  }

  final List<(_Version, String)> others = <(_Version, String)>[
    for (final String t in tags)
      if (_versionOfTag(t.trim()) case final _Version v
          when v.compareTo(current) != 0)
        (v, t.trim()),
  ];
  (_Version, String)? previous;
  for (final (_Version, String) other in others) {
    final bool below = other.$1.compareTo(current) < 0;
    final bool eligible = current.isPrerelease || !other.$1.isPrerelease;
    if (below &&
        eligible &&
        (previous == null || other.$1.compareTo(previous.$1) > 0)) {
      previous = other;
    }
  }
  final bool latest = !current.isPrerelease &&
      others.every(
        ((_Version, String) o) =>
            o.$1.isPrerelease || o.$1.compareTo(current) < 0,
      );

  final List<String> lines = const LineSplitter().convert(section);
  final int firstSubheading = lines.indexWhere(_heading.hasMatch);
  final List<String> intro =
      firstSubheading < 0 ? lines : lines.sublist(0, firstSubheading);
  final List<String> sections =
      firstSubheading < 0 ? const <String>[] : lines.sublist(firstSubheading);

  final List<String> parts = <String>[
    unwrapMarkdown(intro.join('\n')).trim(),
    '```sh\n${installCommand(version, previous: previous?.$1.text)}\n```',
    '[pub.dev](https://pub.dev/packages/jet_print/versions/$version) · '
        '[Changelog]($_repository/blob/$tag/packages/jet_print/CHANGELOG.md)',
    unwrapMarkdown(_promoteHeadings(sections).join('\n')).trim(),
    if (previous != null)
      '**Full changelog:** [`${previous.$1.text}...$version`]'
          '($_repository/compare/${previous.$2}...$tag)',
  ];

  return ReleaseNotes(
    title: 'jet_print $version',
    body: '${parts.where((String p) => p.isNotEmpty).join('\n\n')}\n',
    latest: latest,
    prerelease: current.isPrerelease,
    previousTag: previous?.$2,
  );
}

/// The `## [version]` section of [changelog], without its heading, or null
/// when there is none.
String? changelogSection(String changelog, String version) {
  final RegExp start = RegExp(
    '^## \\[?${RegExp.escape(version)}\\]?(?:\\s|\$)',
  );
  final List<String> lines = const LineSplitter().convert(changelog);
  final int heading = lines.indexWhere(start.hasMatch);
  if (heading < 0) return null;

  final List<String> body = <String>[];
  String? fence;
  for (final String line in lines.skip(heading + 1)) {
    fence = _fenceAfter(line, fence);
    if (fence == null && RegExp(r'^#{1,2}\s').hasMatch(line)) break;
    body.add(line);
  }
  return body.join('\n').trim();
}

/// The command a release's notes tell a host to run.
///
/// A host on the [previous] version's caret range picks up [version] with an
/// upgrade, unless [version] starts a new range: a major release from 1.0, a
/// minor one before it. Then the constraint itself has to move.
String installCommand(String version, {required String? previous}) {
  final _Version current = _Version.tryParse(version)!;
  final _Version? before =
      previous == null ? null : _Version.tryParse(previous);
  if (before != null && before.caretRange == current.caretRange) {
    return 'flutter pub upgrade jet_print';
  }
  return 'flutter pub add jet_print:^$version';
}

/// Joins the hard-wrapped lines of [markdown] so that each paragraph and list
/// item is one line, keeping every line break that Markdown itself renders.
///
/// Fenced code stays verbatim, a block quote is joined inside its markers, and
/// a heading, table row or rule stays a line of its own. A line starting
/// `0006. ` continues a paragraph, as in CommonMark, rather than starting a
/// numbered list, which only `1.` may do in the middle of a paragraph.
String unwrapMarkdown(String markdown) =>
    _unwrap(const LineSplitter().convert(markdown)).join('\n');

final RegExp _fenceOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _quote = RegExp(r'^\s{0,3}>');
final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}(?:\s|$)');
final RegExp _table = RegExp(r'^\s*\|');
final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
final RegExp _bullet = RegExp(r'^\s*[-*+]\s+\S');
final RegExp _numbered = RegExp(r'^\s*(\d{1,9})[.)]\s+\S');
final RegExp _hardBreak = RegExp(r'(?: {2,}|\\)$');

List<String> _unwrap(List<String> lines) {
  final List<String> out = <String>[];
  int i = 0;
  while (i < lines.length) {
    final String line = lines[i];

    if (_fenceOpen.hasMatch(line)) {
      String? fence = _fenceAfter(line, null);
      out.add(line);
      i++;
      while (fence != null && i < lines.length) {
        fence = _fenceAfter(lines[i], fence);
        out.add(lines[i]);
        i++;
      }
      continue;
    }

    if (line.trim().isEmpty) {
      out.add('');
      i++;
      continue;
    }

    if (_quote.hasMatch(line)) {
      final List<String> quoted = <String>[];
      while (i < lines.length && _quote.hasMatch(lines[i])) {
        quoted.add(lines[i].replaceFirst(RegExp(r'^\s{0,3}> ?'), ''));
        i++;
      }
      out.addAll(
        _unwrap(quoted).map((String l) => l.isEmpty ? '>' : '> $l'),
      );
      continue;
    }

    if (_heading.hasMatch(line) ||
        _table.hasMatch(line) ||
        _rule.hasMatch(line)) {
      out.add(line.trimRight());
      i++;
      continue;
    }

    // A paragraph or a list item: join the lines that continue it.
    final bool numbered = _numbered.hasMatch(line);
    String joined = line;
    i++;
    while (i < lines.length && !_hardBreak.hasMatch(joined)) {
      final String next = lines[i];
      if (next.trim().isEmpty || _startsBlock(next, inNumberedList: numbered)) {
        break;
      }
      joined = '${joined.trimRight()} ${next.trim()}';
      i++;
    }
    out.add(joined.replaceFirst(_hardBreak, '').trimRight());
  }
  return out;
}

/// Whether [line] starts a block of its own rather than continuing the
/// paragraph or list item before it.
bool _startsBlock(String line, {required bool inNumberedList}) {
  if (_fenceOpen.hasMatch(line) ||
      _quote.hasMatch(line) ||
      _heading.hasMatch(line) ||
      _table.hasMatch(line) ||
      _rule.hasMatch(line) ||
      _bullet.hasMatch(line)) {
    return true;
  }
  final Match? numbered = _numbered.firstMatch(line);
  return numbered != null &&
      (inNumberedList || int.parse(numbered.group(1)!) == 1);
}

/// The fence still open after [line], given the [open] one before it: the
/// opening marker while inside a fenced block, null outside one.
String? _fenceAfter(String line, String? open) {
  if (open == null) return _fenceOpen.firstMatch(line)?.group(1);
  final String char = RegExp.escape(open[0]);
  final bool closes =
      RegExp('^\\s{0,3}$char{${open.length},}\\s*\$').hasMatch(line);
  return closes ? null : open;
}

/// Raises every heading below `##` one level, outside fenced code: a
/// CHANGELOG version is `##` and its subsections `###`, while in a release
/// body the subsections are the top level.
List<String> _promoteHeadings(List<String> lines) {
  final List<String> out = <String>[];
  String? fence;
  for (final String line in lines) {
    final bool inFence = fence != null;
    fence = _fenceAfter(line, fence);
    out.add(
      !inFence && fence == null && RegExp(r'^#{3,6}\s').hasMatch(line)
          ? line.substring(1)
          : line,
    );
  }
  return out;
}

_Version? _versionOfTag(String tag) => tag.startsWith(tagPrefix)
    ? _Version.tryParse(tag.substring(tagPrefix.length))
    : null;

/// A semantic version, ordered as semver orders them.
class _Version implements Comparable<_Version> {
  _Version(this.text, this.major, this.minor, this.patch, this.pre);

  static final RegExp _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  static _Version? tryParse(String text) {
    final Match? m = _pattern.firstMatch(text);
    if (m == null) return null;
    return _Version(
      text,
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4)?.split('.') ?? const <String>[],
    );
  }

  final String text;
  final int major;
  final int minor;
  final int patch;
  final List<String> pre;

  bool get isPrerelease => pre.isNotEmpty;

  /// What `^version` allows to move: from 1.0 the major version fixes the
  /// range, before it the minor, and before 0.1 the patch.
  String get caretRange => major > 0
      ? '$major'
      : minor > 0
          ? '0.$minor'
          : '0.0.$patch';

  @override
  int compareTo(_Version other) {
    for (final (int a, int b) in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    // A pre-release sorts below the release it precedes.
    if (pre.isEmpty != other.pre.isEmpty) return pre.isEmpty ? 1 : -1;
    for (int i = 0; i < pre.length && i < other.pre.length; i++) {
      final int? a = int.tryParse(pre[i]);
      final int? b = int.tryParse(other.pre[i]);
      final int order = a != null && b != null
          ? a.compareTo(b)
          : a != null
              ? -1
              : b != null
                  ? 1
                  : pre[i].compareTo(other.pre[i]);
      if (order != 0) return order;
    }
    return pre.length.compareTo(other.pre.length);
  }
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr
        .writeln('usage: dart run tool/release_notes.dart <tag> <notes-file>');
    exitCode = 64;
    return;
  }
  final ProcessResult git =
      Process.runSync('git', <String>['tag', '--list', '$tagPrefix*']);
  if (git.exitCode != 0) {
    stderr.write(git.stderr);
    exitCode = 1;
    return;
  }
  try {
    final ReleaseNotes notes = buildReleaseNotes(
      tag: args[0],
      changelog: File('CHANGELOG.md').readAsStringSync(),
      pubspec: File('pubspec.yaml').readAsStringSync(),
      tags: LineSplitter.split(git.stdout as String),
    );
    File(args[1]).writeAsStringSync(notes.body);
    stdout
      ..writeln('title=${notes.title}')
      ..writeln('latest=${notes.latest}')
      ..writeln('prerelease=${notes.prerelease}');
  } on ReleaseNotesException catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 1;
  }
}
