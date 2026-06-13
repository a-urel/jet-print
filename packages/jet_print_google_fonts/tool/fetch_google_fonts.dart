// Maintainer-time tool. Downloads each curated family's four faces from Google
// Fonts, subsets them to the catalog codepoint set with `pyftsubset`, writes
// assets/licenses, and regenerates lib/src/google_font_catalog.dart.
//
// Requires: network access and fonttools (`pip install fonttools brotli`).
// Run from the package root:  dart run tool/fetch_google_fonts.dart
//
// The seed families already committed (Noto Sans/Serif, JetBrains Mono) are
// preserved (the catalog is regenerated from whatever exists under
// assets/fonts/), unless their names also appear in curated_families.dart.
import 'dart:io';

import 'curated_families.dart';

// Basic Latin + Latin-1 + Latin Extended-A + common punctuation — identical to
// the core library's bundled subset (covers Turkish).
const String _unicodes =
    'U+0020-007E,U+00A0-017F,U+2010-2014,U+2018-2022,U+2026,U+20AC,U+2122';

/// One face slot: file suffix, CSS weight, italic flag, JetFontWeight name.
const List<({String suffix, int weight, bool italic, String jetWeight})>
    _faces = <({String suffix, int weight, bool italic, String jetWeight})>[
  (suffix: 'Regular', weight: 400, italic: false, jetWeight: 'normal'),
  (suffix: 'Bold', weight: 700, italic: false, jetWeight: 'bold'),
  (suffix: 'Italic', weight: 400, italic: true, jetWeight: 'normal'),
  (suffix: 'BoldItalic', weight: 700, italic: true, jetWeight: 'bold'),
];

Future<void> main() async {
  for (final (String name, String license, String token) in curatedFamilies) {
    final Directory outDir = Directory('assets/fonts/$name')
      ..createSync(recursive: true);
    final HttpClient client = HttpClient();
    for (final ({String suffix, int weight, bool italic, String jetWeight}) face
        in _faces) {
      final String ital = face.italic ? '1' : '0';
      final Uri css = Uri.parse('https://fonts.googleapis.com/css2'
          '?family=$token:ital,wght@$ital,${face.weight}&display=swap');
      final String cssBody = await _get(client, css,
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)');
      final Match? m =
          RegExp(r'src:\s*url\((https://[^)]+\.ttf)\)').firstMatch(cssBody);
      if (m == null) {
        stderr.writeln('No TTF for $name ${face.suffix}; skipping face.');
        continue;
      }
      final File raw = File('${outDir.path}/.${face.suffix}.full.ttf');
      await raw.writeAsBytes(await _getBytes(client, Uri.parse(m.group(1)!)));
      final String out = '${outDir.path}/${_fileName(name, face.suffix)}';
      // fontTools' subsetter (== pyftsubset). Invoked as a module so it works
      // whether or not the `pyftsubset` CLI is on PATH (`pip install fonttools`).
      final ProcessResult sub = Process.runSync('python3', <String>[
        '-m',
        'fontTools.subset',
        raw.path,
        '--unicodes=$_unicodes',
        '--output-file=$out',
        '--no-hinting',
        '--desubroutinize',
      ]);
      if (sub.exitCode != 0) {
        stderr.writeln('subset failed for $name ${face.suffix}: ${sub.stderr}');
      }
      raw.deleteSync();
    }
    client.close();
    final File lic = File('assets/licenses/$name.txt');
    if (!lic.existsSync()) {
      lic.writeAsStringSync('$license — see fonts.google.com/specimen\n');
    }
    stdout.writeln('Fetched + subset: $name ($license)');
  }
  _regenerateCatalog();
  _regeneratePubspecAssets();
  stdout.writeln('Regenerated google_font_catalog.dart + pubspec assets. '
      'Review licenses, run `flutter test packages/jet_print_google_fonts`, commit.');
}

/// Rewrites the pubspec `flutter: assets:` list with one entry per family
/// directory (Flutter asset dir entries are NOT recursive — each subdirectory
/// must be listed) plus the licenses directory. Keeps everything up to and
/// including the `  assets:` line, then re-emits the list (which sits at EOF).
void _regeneratePubspecAssets() {
  final File f = File('pubspec.yaml');
  final List<String> lines = f.readAsLinesSync();
  final int idx = lines.indexWhere((String l) => l.trimRight() == '  assets:');
  if (idx < 0) {
    stderr
        .writeln('No `  assets:` block in pubspec.yaml; skipping asset regen.');
    return;
  }
  final List<Directory> fams = Directory('assets/fonts')
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
  final StringBuffer out = StringBuffer();
  for (int i = 0; i <= idx; i++) {
    out.writeln(lines[i]);
  }
  for (final Directory d in fams) {
    out.writeln(
        '    - assets/fonts/${d.path.split(Platform.pathSeparator).last}/');
  }
  out.writeln('    - assets/licenses/');
  f.writeAsStringSync(out.toString());
}

String _fileName(String family, String suffix) =>
    '${family.replaceAll(' ', '')}-$suffix.ttf';

/// Re-emits google_font_catalog.dart from whatever families exist under
/// assets/fonts/ (seed + fetched), in directory-sort order.
void _regenerateCatalog() {
  // License per family: from curated_families.dart, with the OFL seed families
  // (Noto Sans/Serif, JetBrains Mono) defaulting to OFL-1.1.
  final Map<String, String> licenseOf = <String, String>{
    'Noto Sans': 'OFL-1.1',
    'Noto Serif': 'OFL-1.1',
    'JetBrains Mono': 'OFL-1.1',
    for (final (String name, String license, String _) in curatedFamilies)
      name: license,
  };
  final List<Directory> families = Directory('assets/fonts')
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
  final StringBuffer out = StringBuffer('''
// GENERATED by tool/fetch_google_fonts.dart — do not edit by hand.
library;

import 'package:jet_print/jet_print.dart' show JetFontWeight;

import 'google_font_entry.dart';

const String _base = 'packages/jet_print_google_fonts/assets/fonts';

/// Every family bundled with this package, in catalog order.
const List<GoogleFontEntry> googleFontCatalog = <GoogleFontEntry>[
''');
  for (final Directory fam in families) {
    final String name = fam.path.split(Platform.pathSeparator).last;
    out.writeln('  GoogleFontEntry(');
    out.writeln("    name: '$name',");
    out.writeln("    license: '${licenseOf[name] ?? 'OFL-1.1'}',");
    out.writeln('    faceAssets: <FontFaceSlot, String>{');
    for (final ({String suffix, int weight, bool italic, String jetWeight}) face
        in _faces) {
      final String file = _fileName(name, face.suffix);
      if (File('${fam.path}/$file').existsSync()) {
        out.writeln("      (weight: JetFontWeight.${face.jetWeight}, "
            "italic: ${face.italic}): '\$_base/$name/$file',");
      }
    }
    out.writeln('    },');
    out.writeln('  ),');
  }
  out.writeln('];');
  File('lib/src/google_font_catalog.dart').writeAsStringSync(out.toString());
}

Future<String> _get(HttpClient c, Uri u, {required String userAgent}) async {
  final HttpClientRequest req = await c.getUrl(u);
  req.headers.set(HttpHeaders.userAgentHeader, userAgent);
  final HttpClientResponse res = await req.close();
  return res.transform(const SystemEncoding().decoder).join();
}

Future<List<int>> _getBytes(HttpClient c, Uri u) async {
  final HttpClientResponse res = await (await c.getUrl(u)).close();
  final List<int> bytes = <int>[];
  await for (final List<int> chunk in res) {
    bytes.addAll(chunk);
  }
  return bytes;
}
