// JetReportPrinter (012 — contract B6; FR-009a; T021).
//
// The print capability behind an injected fake PrintDialogPresenter — no
// platform channels in tests: the presenter receives the SAME deterministic
// bytes toPdf produces plus the template's page dimensions and a job name;
// user cancellation returns false (not an error); an unavailable platform
// surfaces a specific, identifiable PrintUnavailableException — never a
// crash, never a silent no-op.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/print/jet_report_printer.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import '../rendering/export/support/export_fixtures.dart';

/// Records one presenter invocation.
class _PresenterCall {
  _PresenterCall(this.bytes,
      {required this.jobName,
      required this.pageWidthPt,
      required this.pageHeightPt});

  final Uint8List bytes;
  final String jobName;
  final double pageWidthPt;
  final double pageHeightPt;
}

/// A fake presenter capturing its call and answering [result].
class _FakePresenter {
  _FakePresenter({this.result = true});

  final bool result;
  final List<_PresenterCall> calls = <_PresenterCall>[];

  Future<bool> call(
    Uint8List pdfBytes, {
    required String jobName,
    required double pageWidthPt,
    required double pageHeightPt,
  }) async {
    calls.add(_PresenterCall(pdfBytes,
        jobName: jobName,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt));
    return result;
  }
}

void main() {
  test('the presenter receives the toPdf bytes and the true page size',
      () async {
    final _FakePresenter presenter = _FakePresenter();
    final bool sent = await JetReportPrinter(presenter: presenter.call)
        .printReport(invoiceReport());
    expect(sent, isTrue);
    final _PresenterCall call = presenter.calls.single;
    // Byte-determinism (B3) makes this equality meaningful: the job is the
    // exact artifact toPdf exports — the document IS what prints.
    expect(call.bytes, await const JetReportExporter().toPdf(invoiceReport()));
    expect(call.pageWidthPt, 400, reason: 'invoice template page width (pt)');
    expect(call.pageHeightPt, 300, reason: 'invoice template page height (pt)');
  });

  group('job name', () {
    test('defaults to the non-empty report title', () async {
      final _FakePresenter presenter = _FakePresenter();
      await JetReportPrinter(presenter: presenter.call)
          .printReport(invoiceReport());
      expect(presenter.calls.single.jobName, 'Invoice');
    });

    test('an explicit jobName wins', () async {
      final _FakePresenter presenter = _FakePresenter();
      await JetReportPrinter(presenter: presenter.call)
          .printReport(invoiceReport(), jobName: 'Quarterly');
      expect(presenter.calls.single.jobName, 'Quarterly');
    });

    test('falls back to "Report" when the title is empty', () async {
      final RenderedReport untitled = const JetReportEngine().renderDefinition(
        const ReportDefinition(
          name: '',
          page: PageFormat.a4Portrait,
          body: ReportBody(root: DetailScope(id: 'root')),
        ),
        JetInMemoryDataSource(const <Map<String, Object?>>[]),
      );
      expect(untitled.title, isEmpty, reason: 'fixture sanity');
      final _FakePresenter presenter = _FakePresenter();
      await JetReportPrinter(presenter: presenter.call).printReport(untitled);
      expect(presenter.calls.single.jobName, 'Report');
    });
  });

  test('user cancellation returns false — not an error', () async {
    final _FakePresenter presenter = _FakePresenter(result: false);
    final bool sent = await JetReportPrinter(presenter: presenter.call)
        .printReport(invoiceReport());
    expect(sent, isFalse);
    expect(presenter.calls, hasLength(1),
        reason: 'the dialog was presented; the user declined');
  });

  test(
      'an unavailable platform surfaces PrintUnavailableException with an '
      'identifying message — never a crash, never a silent no-op', () async {
    Future<bool> unavailable(
      Uint8List pdfBytes, {
      required String jobName,
      required double pageWidthPt,
      required double pageHeightPt,
    }) async {
      throw const PrintUnavailableException(
          'printing is not available on FakeOS');
    }

    await expectLater(
      JetReportPrinter(presenter: unavailable).printReport(invoiceReport()),
      throwsA(isA<PrintUnavailableException>().having(
          (PrintUnavailableException e) => e.toString(),
          'toString',
          contains('FakeOS'))),
    );
  });

  test('JetReportPrinter is const-constructible (default presenter)', () {
    expect(const JetReportPrinter(), isA<JetReportPrinter>());
  });
}
