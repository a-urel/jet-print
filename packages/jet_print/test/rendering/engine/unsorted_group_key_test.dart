// A group key that comes back is reported (api-friction entry 5).
//
// A group breaks when its key differs from the previous row's, so a source not
// ordered by the key prints the same group twice, with nothing wrong on the
// page to say why. Render now warns, once per group level, the first time a
// key value reappears within one instance of its parent group. The report
// itself is unchanged: the warning names the cause, it does not sort.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

Band _band(String id, BandType type) => Band(
      id: id,
      type: type,
      height: 16,
      elements: <ReportElement>[
        TextElement(
          id: '$id-text',
          bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
          text: id,
        ),
      ],
    );

/// Groups by class, then by account within it.
ReportDefinition _twoLevels() => ReportDefinition(
      name: 'ledger',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'cls',
              name: 'Class',
              key: r'$F{cls}',
              header: _band('clsHeader', BandType.groupHeader),
            ),
            GroupLevel(
              id: 'acc',
              name: 'Account',
              key: r'$F{acc}',
              header: _band('accHeader', BandType.groupHeader),
            ),
          ],
          children: <ScopeNode>[BandNode(_band('detail', BandType.detail))],
        ),
      ),
    );

List<Diagnostic> _render(List<Map<String, Object?>> rows) {
  final RenderedReport report = const JetReportEngine()
      .renderDefinition(_twoLevels(), JetInMemoryDataSource(rows));
  expect(report.pageCount, greaterThan(0));
  return report.diagnostics.entries
      .where((Diagnostic d) => d.message.contains('not sorted'))
      .toList();
}

Map<String, Object?> _row(String cls, String acc) =>
    <String, Object?>{'cls': cls, 'acc': acc};

void main() {
  test('a sorted source draws no warning', () {
    expect(
        _render(<Map<String, Object?>>[
          _row('A', '1'),
          _row('A', '2'),
          _row('B', '1'),
        ]),
        isEmpty,
        reason: 'account 1 under class B is a new parent, not a repeat');
  });

  test('an outer key that comes back warns once, naming the group and key', () {
    final List<Diagnostic> found = _render(<Map<String, Object?>>[
      _row('A', '1'),
      _row('B', '1'),
      _row('A', '1'),
      _row('B', '1'),
      _row('A', '1'),
    ]);
    expect(found, hasLength(1), reason: 'one warning per group level');
    expect(found.single.severity, DiagnosticSeverity.warning);
    expect(found.single.message, contains('"Class"'));
    expect(found.single.message, contains('A'));
  });

  test('an inner key that comes back within one parent warns for that level',
      () {
    final List<Diagnostic> found = _render(<Map<String, Object?>>[
      _row('A', '1'),
      _row('A', '2'),
      _row('A', '1'),
    ]);
    expect(found, hasLength(1));
    expect(found.single.message, contains('"Account"'));
  });
}
