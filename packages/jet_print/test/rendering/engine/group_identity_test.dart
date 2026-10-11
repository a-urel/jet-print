// A group is keyed by its id; its name is a display label only (#100).
//
// The engine used to key groups by `GroupLevel.name` internally, so the name
// had to be unique in a scope and `ReportVariable.resetGroup` resolved against
// both the id and the name. Now the id is the only key: two groups may share a
// name, a reset names its group by id, and renaming a group changes nothing the
// report prints.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart'
    show frameOf;
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;

const PageFormat _page =
    PageFormat(width: 400, height: 600, margins: JetEdgeInsets.all(10));

// Numbers print through a fixed pattern: a stringified whole double reads
// "1.0" on the VM and "1" on the web.
TextElement _text(String id, String expression) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 360, height: 16),
      text: id,
      expression: expression,
      format: '0',
    );

Band _band(String id, BandType type, String expression) => Band(
      id: id,
      type: type,
      height: 18,
      elements: <ReportElement>[_text(id, expression)],
    );

/// A report grouped by region, then by city: each group has a header printing
/// its key and a footer printing `SUM($F{amount})`, and a per-city variable
/// resets on the city group by [cityResetGroup].
ReportDefinition _grouped({
  String regionName = 'Region',
  String cityName = 'City',
  String cityResetGroup = 'g/city',
}) =>
    ReportDefinition(
      name: 'groups',
      page: _page,
      variables: <ReportVariable>[
        ReportVariable(
          name: 'cityRows',
          expression: '1',
          calculation: JetCalculation.count,
          resetScope: VariableResetScope.group,
          resetGroup: cityResetGroup,
        ),
      ],
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'g/region',
              name: regionName,
              key: r'$F{region}',
              header: _band('rh', BandType.groupHeader, r'$F{region}'),
              footer: _band('rf', BandType.groupFooter, r'SUM($F{amount})'),
            ),
            GroupLevel(
              id: 'g/city',
              name: cityName,
              key: r'$F{city}',
              header: _band('ch', BandType.groupHeader, r'$F{city}'),
              footer: _band('cf', BandType.groupFooter, r'$V{cityRows}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(_band('d', BandType.detail, r'$F{amount}')),
          ],
        ),
      ),
    );

final JetInMemoryDataSource _rows = JetInMemoryDataSource(
  const <Map<String, Object?>>[
    <String, Object?>{'region': 'North', 'city': 'Oslo', 'amount': 1},
    <String, Object?>{'region': 'North', 'city': 'Oslo', 'amount': 2},
    <String, Object?>{'region': 'North', 'city': 'Bergen', 'amount': 4},
    <String, Object?>{'region': 'South', 'city': 'Rome', 'amount': 8},
  ],
  fields: const <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('city', type: JetFieldType.string),
    FieldDef('amount', type: JetFieldType.integer),
  ],
);

/// Every printed text run, in page order, as `elementId=text`.
List<String> _printed(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final FramePrimitive p in frameOf(report.pageAt(i)).primitives)
          if (p is TextRunPrimitive)
            '${p.elementId}=${p.lines.map((TextLine l) => l.text).join()}',
    ];

RenderedReport _render(ReportDefinition def, {RenderOptions? options}) =>
    const JetReportEngine().renderDefinition(def, _rows,
        options: options ?? const RenderOptions());

List<Diagnostic> _errors(ReportDefinition def) => <Diagnostic>[
      for (final Diagnostic d in validate(def))
        if (d.severity == DiagnosticSeverity.error) d,
    ];

const List<String> _expected = <String>[
  'rh=North',
  'ch=Oslo',
  'd=1',
  'd=2',
  'cf=2',
  'ch=Bergen',
  'd=4',
  'cf=1',
  'rf=7',
  'rh=South',
  'ch=Rome',
  'd=8',
  'cf=1',
  'rf=8',
];

void main() {
  test('groups with distinct ids and names render each level', () {
    expect(_errors(_grouped()), isEmpty);
    expect(_printed(_render(_grouped())), _expected);
  });

  test('two groups may share a name', () {
    final ReportDefinition def =
        _grouped(regionName: 'Level', cityName: 'Level');
    expect(_errors(def), isEmpty,
        reason: 'the name is a label, so a duplicate is not an error');
    expect(_printed(_render(def)), _expected);
  });

  test('renaming a group changes nothing the report prints', () {
    final RenderedReport before = _render(_grouped());
    final RenderedReport after =
        _render(_grouped(regionName: 'Area', cityName: 'Town'));
    expect(after.pageCount, before.pageCount);
    for (int i = 0; i < before.pageCount; i++) {
      expect(frameOf(after.pageAt(i)), frameOf(before.pageAt(i)));
    }
  });

  test('a reset names its group by id, even when it is another group name', () {
    // `g/city` is the city group's id and also the region group's name: the
    // reference is the id, so it is not ambiguous and resets per city.
    final ReportDefinition def = _grouped(regionName: 'g/city');
    expect(_errors(def), isEmpty);
    expect(_printed(_render(def)), _expected);
  });

  test('a reset that names a group by its name is not a reference', () {
    final ReportDefinition def = _grouped(cityResetGroup: 'City');
    expect(
        _errors(def).map((Diagnostic d) => d.message),
        contains(allOf(contains('variable "cityRows" resets on group "City"'),
            contains('not a group'))));
  });

  test('the print callback sees the group name, not its id', () {
    final Set<String?> names = <String?>{};
    // Pages are built lazily, and the callback fires as each one is built.
    _printed(_render(
      _grouped(),
      options: RenderOptions(
        onElementPrint: (ReportElement el, ElementPrintContext ctx) {
          if (ctx.bandType == BandType.groupHeader) names.add(ctx.bandName);
          return el;
        },
      ),
    ));
    expect(names, <String>{'Region', 'City'});
  });

  group('pagination flags follow the id', () {
    // A short page, so the report spans several. Region starts each instance
    // on a new page and reprints its header on continuation pages; city keeps
    // each instance on one page. The layouter reads all three flags through
    // the group's id, so a lookup by name would lose or swap them.
    const PageFormat shortPage =
        PageFormat(width: 400, height: 140, margins: JetEdgeInsets.all(10));

    ReportDefinition paged({required String region, required String city}) =>
        ReportDefinition(
          name: 'paged',
          page: shortPage,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'region',
                  name: region,
                  key: r'$F{region}',
                  startNewPage: true,
                  reprintHeaderOnEachPage: true,
                  header: _band('rh', BandType.groupHeader, r'$F{region}'),
                ),
                GroupLevel(
                  id: 'city',
                  name: city,
                  key: r'$F{city}',
                  keepTogether: true,
                  header: _band('ch', BandType.groupHeader, r'$F{city}'),
                  footer: _band('cf', BandType.groupFooter, r'$F{city}'),
                ),
              ],
              children: <ScopeNode>[
                BandNode(_band('d', BandType.detail, r'$F{amount}')),
              ],
            ),
          ),
        );

    final JetInMemoryDataSource rows = JetInMemoryDataSource(
      <Map<String, Object?>>[
        for (final (String region, String city, int n)
            in <(String, String, int)>[
          ('North', 'Oslo', 3),
          ('North', 'Bergen', 3),
          ('South', 'Rome', 2),
        ])
          for (int i = 0; i < n; i++)
            <String, Object?>{'region': region, 'city': city, 'amount': i},
      ],
    );

    List<List<String>> pages(ReportDefinition def) {
      final RenderedReport r =
          const JetReportEngine().renderDefinition(def, rows);
      return <List<String>>[
        for (int i = 0; i < r.pageCount; i++)
          <String>[
            for (final FramePrimitive p in frameOf(r.pageAt(i)).primitives)
              if (p is TextRunPrimitive)
                '${p.elementId}=${p.lines.map((TextLine l) => l.text).join()}',
          ],
      ];
    }

    final List<List<String>> reference =
        pages(paged(region: 'region', city: 'city'));

    test('the reference exercises all three flags', () {
      expect(reference.length, greaterThan(2));
      // startNewPage + reprintHeaderOnEachPage: every page opens on a region
      // header, and South's first page holds no North row.
      for (final List<String> page in reference) {
        expect(page.first, startsWith('rh='), reason: '$page');
      }
      final List<String> south =
          reference.firstWhere((List<String> p) => p.first == 'rh=South');
      expect(south, isNot(contains('ch=Oslo')));
      expect(south, isNot(contains('ch=Bergen')));
      // keepTogether: each city header lands on the page of its footer.
      for (final String city in <String>['Oslo', 'Bergen', 'Rome']) {
        final List<String> page =
            reference.firstWhere((List<String> p) => p.contains('ch=$city'));
        expect(page, contains('cf=$city'), reason: '$city split: $reference');
      }
    });

    test('names unrelated to the ids paginate identically', () {
      expect(pages(paged(region: 'Area', city: 'Town')), reference);
    });

    test("names that are each other's ids paginate identically", () {
      expect(pages(paged(region: 'city', city: 'region')), reference);
    });
  });
}
