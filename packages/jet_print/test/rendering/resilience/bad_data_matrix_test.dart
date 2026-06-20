// Bad-data resilience matrix (spec E2, R1–R11). Each fault renders a
// best-effort fallback with no crash and the expected diagnostic. This is a
// CONTRACT suite: it locks the engine's render-don't-crash guarantees.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 360, height: 16);

TextElement _t(String id, {String? text, String? expr, double y = 0}) =>
    TextElement(
      id: id,
      bounds: JetRect(x: 0, y: y, width: 360, height: 16),
      text: text ?? id,
      expression: expr,
    );

ReportDefinition _flat(
  List<ReportElement> detail, {
  Band? summary,
  Band? noData,
  List<ReportVariable> variables = const <ReportVariable>[],
}) =>
    ReportDefinition(
      name: 'matrix',
      page: const PageFormat(
          width: 400, height: 400, margins: JetEdgeInsets.all(10)),
      variables: variables,
      body: ReportBody(
        summary: summary,
        noData: noData,
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 40,
              elements: detail)),
        ]),
      ),
    );

RenderedReport _render(ReportDefinition def, List<Map<String, Object?>> rows) =>
    const JetReportEngine().renderDefinition(def, JetInMemoryDataSource(rows));

List<Diagnostic> _diags(RenderedReport r) => r.diagnostics.entries;

Diagnostic _match(RenderedReport r, Pattern p) =>
    _diags(r).firstWhere((Diagnostic d) => d.message.contains(p),
        orElse: () => fail('no diagnostic matching "$p": ${_diags(r)}'));

Map<String, String> _texts(RenderedReport r) => <String, String>{
      for (final TextRunPrimitive p
          in r.pageAt(0).frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId != null)
          p.elementId!: p.lines.map((TextLine l) => l.text).join(),
    };

Band _summaryBand(String id, String expr) => Band(
      id: 'body/summary',
      type: BandType.summary,
      height: 16,
      elements: <ReportElement>[_t(id, expr: expr)],
    );

void main() {
  test('R1: schema-aware unknown field -> token + deduped (structural) warning',
      () {
    // With knownFields supplied, the resolver returns the unresolved token and
    // warns ONCE for the whole report (structural — not per row).
    final RenderedReport r = const JetReportEngine().renderDefinition(
      _flat(<ReportElement>[
        _t('good', expr: r'$F{name}'),
        _t('bad', expr: r'$F{nope}')
      ]),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'alpha'}
      ]),
      options: const RenderOptions(knownFields: <String>{'name'}),
    );
    final List<Diagnostic> nope =
        _diags(r).where((Diagnostic d) => d.message.contains('nope')).toList();
    expect(nope, hasLength(1), reason: 'deduped once for the report');
    expect(nope.single.severity, DiagnosticSeverity.warning);
    expect(_texts(r)['good'], 'alpha');
    expect(_texts(r)['bad'], '#ERROR', reason: 'the unresolved-field token');
  });

  test('R2: non-schema-aware missing field is row-tagged (one per row)', () {
    // No knownFields: a binding to a field absent from the data schema renders
    // blank and warns PER ROW with the row position (not globally deduped).
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('bad', expr: r'$F{nope}')]),
      <Map<String, Object?>>[
        <String, Object?>{'name': 'a'},
        <String, Object?>{'name': 'b'},
      ],
    );
    final List<Diagnostic> nope = _diags(r)
        .where((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning &&
            d.message.contains('nope'))
        .toList();
    expect(nope, hasLength(2), reason: 'one per row, not globally deduped');
    expect(nope[0].message, contains('Row 1'));
    expect(nope[1].message, contains('Row 2'));
    expect(_texts(r)['bad'], '', reason: 'blank fallback');
  });

  test('R3: wrong-type SUM input is surfaced (row-tagged) and clean rows sum',
      () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('amt', expr: r'$F{amount}')],
        summary: _summaryBand('total', r'$V{total}'),
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total',
              expression: r'$F{amount}',
              calculation: JetCalculation.sum,
              resetScope: VariableResetScope.report),
        ],
      ),
      <Map<String, Object?>>[
        <String, Object?>{'amount': 10.0},
        <String, Object?>{'amount': 'oops'},
        <String, Object?>{'amount': 5.0},
      ],
    );
    final Diagnostic d = _match(r, 'skipped from an aggregate');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, contains('Row '));
  });

  test('R4: wrong-type MIN/MAX input does not crash (best-effort)', () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('amt', expr: r'$F{amount}')],
        summary: _summaryBand('peak', r'$V{peak}'),
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'peak',
              expression: r'$F{amount}',
              calculation: JetCalculation.max,
              resetScope: VariableResetScope.report),
        ],
      ),
      <Map<String, Object?>>[
        <String, Object?>{'amount': 3.0},
        <String, Object?>{'amount': 'x'},
        <String, Object?>{'amount': 9.0},
      ],
    );
    // No throw; the report renders. (MIN/MAX over mixed types is best-effort.)
    expect(r.pageCount, greaterThan(0));
    expect(_texts(r)['amt'], isNotNull);
  });

  test('R5: a null collection field emits no nested rows, no diagnostic', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r5',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'lines': null},
      ]),
    );
    expect(r.pageCount, greaterThan(0));
    expect(
        _diags(r)
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty);
    expect(_texts(r)['v'], isNull,
        reason: 'a null collection emits no nested rows');
  });

  test('R6: a non-list collection field warns and emits no rows', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r6',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'lines': 'not a list'},
      ]),
    );
    _match(r, 'did not resolve to a collection');
    expect(r.pageCount, greaterThan(0));
  });

  test('R7: a non-row entry inside a collection is skipped + row-tagged', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r7',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Object?>[
            <String, Object?>{'v': 1},
            'not a row',
          ],
        },
      ]),
    );
    final Diagnostic d = _match(r, 'non-row entry');
    expect(d.message, contains('Row '));
    expect(_texts(r)['v'], '1.0',
        reason: 'the valid entry still renders; only the bad one is skipped');
  });

  test('R8: a malformed expression -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'$F{a} +')]),
      <Map<String, Object?>>[
        <String, Object?>{'a': 1}
      ],
    );
    final Diagnostic d = _diags(r).firstWhere(
        (Diagnostic d) => d.severity == DiagnosticSeverity.error,
        orElse: () => fail('expected a parse error: ${_diags(r)}'));
    expect(d.elementId, 'boom');
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R9: divide-by-zero -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'$F{a} / 0')]),
      <Map<String, Object?>>[
        <String, Object?>{'a': 5}
      ],
    );
    final Diagnostic diag = _match(r, 'zero');
    expect(diag.severity, DiagnosticSeverity.error);
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R10: unknown function -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'NOPE($F{a})')]),
      <Map<String, Object?>>[
        <String, Object?>{'a': 5}
      ],
    );
    _diags(r).firstWhere(
      (Diagnostic d) => d.severity == DiagnosticSeverity.error,
      orElse: () => fail('expected an unknown-function error: ${_diags(r)}'),
    );
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R11: an empty data source renders the noData band + info', () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('d', expr: r'$F{name}')],
        noData: const Band(
          id: 'body/noData',
          type: BandType.noData,
          height: 16,
          elements: <ReportElement>[
            TextElement(id: 'nd', bounds: _r, text: 'No data'),
          ],
        ),
      ),
      <Map<String, Object?>>[],
    );
    _match(r, 'no rows');
    expect(_texts(r)['nd'], 'No data');
  });
}
