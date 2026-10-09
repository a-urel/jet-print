// The package example (example/jet_print_example.dart) is the first code a
// pub.dev reader runs, so it must keep compiling and doing what it says against
// the public API. Importing it here puts it under the analyzer and the suite.
//
// VM only: the browser test runner serves just `test/`, so it cannot load a
// file from `example/`; the conditional import below keeps the Chrome bundle
// compiling. The web render and export path is covered by
// `test/web/web_render_export_test.dart`.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/example_web.dart'
    if (dart.library.io) 'support/example_io.dart';

void main() {
  test('the example report fills cleanly onto one page', () {
    final RenderedReport report = renderGreetings(const <String>['Ada', 'Bo']);
    expect(report.pageCount, 1);
    report.pageAt(0); // pages fill lazily; diagnostics arrive with the page
    expect(report.diagnostics.entries, isEmpty,
        reason: 'the greeting expression binds to the name field');
  });

  test('the example exports a PDF', () async {
    final Uint8List pdf =
        await exportGreetingsPdf(const <String>['Ada', 'Grace']);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  testWidgets('the example app previews the report',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GreetingsApp(
      report: renderGreetings(const <String>['Ada', 'Grace']),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(JetReportPreview), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });
}
