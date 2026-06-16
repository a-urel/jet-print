import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';

TextElement _txt(String id, {String? expression}) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
      text: id,
      expression: expression,
    );

/// A fully valid definition: page chrome (static only) + title + one master
/// group + a nested `lines` scope with a single per-row band.
ReportDefinition _valid({
  PageFurniture? furniture,
  ReportBody? body,
}) =>
    ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      furniture: furniture ??
          const PageFurniture(
            pageHeader: Band(
                id: 'furniture/pageHeader',
                type: BandType.pageHeader,
                height: 20),
          ),
      body: body ??
          const ReportBody(
            title: Band(id: 'body/title', type: BandType.title, height: 24),
            root: DetailScope(
              id: 'root',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'root/g0',
                  name: 'invoice',
                  key: r'$F{invoiceNo}',
                  header: Band(
                      id: 'root/g0/header',
                      type: BandType.groupHeader,
                      height: 20),
                  footer: Band(
                      id: 'root/g0/footer',
                      type: BandType.groupFooter,
                      height: 20),
                ),
              ],
              children: <ScopeNode>[
                NestedScope(DetailScope(
                  id: 'root/c0',
                  collectionField: 'lines',
                  children: <ScopeNode>[
                    BandNode(Band(
                        id: 'root/c0/c0', type: BandType.detail, height: 16)),
                  ],
                )),
              ],
            ),
          ),
    );

bool _has(List<Diagnostic> ds, DiagnosticSeverity sev, String needle) =>
    ds.any((Diagnostic d) =>
        d.severity == sev && d.message.toLowerCase().contains(needle));

void main() {
  group('validate', () {
    test('returns empty for a valid definition', () {
      expect(validate(_valid()), isEmpty);
    });

    test('never throws (even on a malformed key)', () {
      expect(
        () => validate(_valid(
            body: const ReportBody(
                root: DetailScope(id: 'root', groups: <GroupLevel>[
          GroupLevel(id: 'g', name: 'n', key: ')('),
        ])))),
        returnsNormally,
      );
    });

    test('I1 flags a duplicate id', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          title: Band(id: 'dup', type: BandType.title, height: 10),
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(id: 'dup', type: BandType.detail, height: 10)),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'duplicate id'),
          isTrue);
    });

    test('I2 flags a duplicate group name within a scope', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'same', key: '1'),
            GroupLevel(id: 'g2', name: 'same', key: '2'),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'name'), isTrue);
    });

    test('I3 flags an unparseable group key', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(id: 'g', name: 'n', key: ')('),
          ]),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'parse'), isTrue);
    });

    test('I4 flags a field binding on record-blind furniture', () {
      final ReportDefinition def = _valid(
        furniture: PageFurniture(
          pageHeader: Band(
            id: 'furniture/pageHeader',
            type: BandType.pageHeader,
            height: 20,
            elements: <ReportElement>[_txt('f', expression: r'$F{name}')],
          ),
        ),
      );
      final List<Diagnostic> ds = validate(def);
      expect(_has(ds, DiagnosticSeverity.warning, 'field'), isTrue);
    });

    test('I4 flags a field binding on a record-blind title band', () {
      final ReportDefinition def = _valid(
        body: ReportBody(
          title: Band(
            id: 'body/title',
            type: BandType.title,
            height: 20,
            elements: <ReportElement>[_txt('t', expression: r'$F{name}')],
          ),
          root: const DetailScope(id: 'root'),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.warning, 'field'), isTrue);
    });

    test('I5 flags a band whose type is inconsistent with its slot', () {
      final ReportDefinition def = _valid(
        furniture: const PageFurniture(
          pageHeader: Band(
              id: 'furniture/pageHeader', type: BandType.detail, height: 20),
        ),
      );
      expect(_has(validate(def), DiagnosticSeverity.error, 'type'), isTrue);
    });

    test('I6 flags a nested scope missing its collectionField', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(id: 'root/c0')),
          ]),
        ),
      );
      expect(
          _has(validate(def), DiagnosticSeverity.error, 'collection'), isTrue);
    });

    test('I6 flags a root scope that carries a collectionField', () {
      final ReportDefinition def = _valid(
        body: const ReportBody(
          root: DetailScope(id: 'root', collectionField: 'oops'),
        ),
      );
      expect(
          _has(validate(def), DiagnosticSeverity.error, 'collection'), isTrue);
    });

    test('an inline aggregate outside summary/group-footer is an error', () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: 16,
              elements: <ReportElement>[
                TextElement(
                  id: 'bad',
                  bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                  text: 'bad',
                  expression: r'SUM($F{amount})',
                ),
              ],
            )),
          ]),
        ),
      );
      final errors = validate(def)
          .where((d) => d.severity == DiagnosticSeverity.error)
          .map((d) => d.message);
      expect(errors, anyElement(contains('aggregate')));
    });

    test('an inline aggregate in summary is valid (no aggregate diagnostic)',
        () {
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          summary: Band(
            id: 's',
            type: BandType.summary,
            height: 16,
            elements: <ReportElement>[
              TextElement(
                id: 'ok',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                text: 'ok',
                expression: r'SUM($F{amount})',
              ),
            ],
          ),
          root: const DetailScope(id: 'root'),
        ),
      );
      expect(
          validate(def).where((d) => d.message.contains('aggregate')), isEmpty);
    });

    test(
        'an inline aggregate in a group FOOTER is valid, but in a group HEADER '
        'is an error', () {
      Band band(String id, BandType type) => Band(
            id: id,
            type: type,
            height: 16,
            elements: <ReportElement>[
              TextElement(
                id: '$id.el',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
                text: id,
                expression: r'SUM($F{amount})',
              ),
            ],
          );
      final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
            GroupLevel(
              id: 'g',
              name: 'g',
              key: r'$F{k}',
              header: band('gh', BandType.groupHeader),
              footer: band('gf', BandType.groupFooter),
            ),
          ]),
        ),
      );
      final aggErrors = validate(def)
          .where((d) => d.severity == DiagnosticSeverity.error)
          .where((d) => d.message.contains('aggregate'))
          .toList();
      expect(aggErrors, hasLength(1),
          reason: 'header aggregate flagged, footer aggregate allowed');
      expect(aggErrors.single.elementId, 'gh.el');
    });
  });
}
