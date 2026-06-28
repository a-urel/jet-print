// Widget test: the Outline's report-root "+" menu creates an empty singleton
// band (report header/footer, page header/footer, no-data) and selects it;
// occupied slots are not offered, and the reserved column/background types are
// never offered.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

// A report that already owns a report header (body.title) so its add option
// should be suppressed.
ReportDefinition _withTitle() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 't', type: BandType.title, height: 24),
        root: DetailScope(id: 'root'),
      ),
    );

void main() {
  testWidgets('report "+" adds a report header into body.title and selects it',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _openOutline(tester);

    expect(c.definition.body.title, isNull);
    await _tapKey(tester, 'jet_print.designer.outline.report.add');
    await _tapKey(tester, 'jet_print.designer.outline.report.add.title');

    final Band? title = c.definition.body.title;
    expect(title, isNotNull);
    expect(title!.type, BandType.title);
    expect(c.selection.bandId, title.id,
        reason: 'the freshly added band is selected');
  });

  testWidgets('an occupied slot is not offered, reserved types never appear',
      (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: _withTitle(),
    );
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.report.add');
    // body.title is occupied → its add option is absent.
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.title')),
        findsNothing);
    // A free slot is still offered.
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.summary')),
        findsOneWidget);
    // Reserved (unrendered) types are never listed.
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.columnHeader')),
        findsNothing);
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.background')),
        findsNothing);
  });
}
