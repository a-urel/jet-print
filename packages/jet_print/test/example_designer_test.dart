// example/designer_example.dart is the README's "Host the designer" and
// "Save and reopen" code. These tests keep it compiling and working against the
// public API; see example_test.dart for why the import is conditional.
@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/example_web.dart'
    if (dart.library.io) 'support/example_io.dart';

void main() {
  testWidgets('the designer example hosts a working workspace',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const DesignerApp());
    await tester.pumpAndSettle();
    expect(find.byType(JetReportWorkspace), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a saved report reopens unchanged', () {
    final JetReportDesignerController source = JetReportDesignerController(
        definition: salesByRegion); // any non-blank design
    addTearDown(source.dispose);
    final JetReportDesignerController target = JetReportDesignerController();
    addTearDown(target.dispose);

    openReport(target, saveReport(source));

    expect(target.definition, source.definition);
  });

  test('the sample rows render against the designer schema', () {
    expect(validate(greetingsReport, schema: customerSchema), isEmpty);
  });
}
