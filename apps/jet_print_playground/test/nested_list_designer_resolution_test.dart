// Designer regression on the REAL spec-030 nested-list sample (spec 031): the
// playground's `nestedListsDefinition()` references three PUBLISHED scope totals
// — they are injected at fill time onto parent rows, NOT schema fields — so the
// Properties panel must resolve a binding to each WITHOUT the "Field not found"
// flag, while a genuine typo must still flag. This is the exact shape the user
// saw mis-flagged before Tasks 1-3.
//
// Unlike `packages/jet_print/test/designer/published_total_resolution_test.dart`
// (a synthetic minimal analogue), this test drives the ACTUAL sample the
// playground ships, importable only from this cross-package test dir. It pumps
// the public `JetReportDesigner` widget over `customersSchema`, the way the
// playground app itself wires it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/nested_list_sample.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _unresolvedMsg = 'Field not found in the data source';

/// The value-field picker trigger key (must match `properties_panel.dart`'s
/// `_FieldPicker` default `keyPrefix`).
const ValueKey<String> _valuePickKey =
    ValueKey<String>('jet_print.designer.properties.field.value.pick');

Finder _valuePickItem(String field) => find.byKey(
    ValueKey<String>('jet_print.designer.properties.field.value.pick.$field'));

/// Pumps the public [JetReportDesigner] over the REAL nested-list sample +
/// [customersSchema], exactly as the playground app wires it, and returns the
/// controller so the test can select elements and assert the panel.
Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final JetReportDesignerController c =
      JetReportDesignerController(definition: nestedListsDefinition());
  addTearDown(c.dispose);
  final Widget app = ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    home: JetReportDesigner(controller: c, dataSchema: customersSchema),
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return c;
}

/// Opens the right panel's Properties tab in any locale (mirrors the package
/// harness's `openPropertiesTab`).
Future<void> _openProperties(WidgetTester tester) async {
  final JetPrintLocalizations l10n = JetPrintLocalizations.of(
    tester.element(find.byType(JetReportDesigner)),
  );
  final Finder tab = find.text(l10n.tabProperties);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Selects [elementId] and opens its Properties so the binding diagnostic (and
/// the value picker) are on-screen.
Future<void> _selectAndInspect(WidgetTester tester,
    JetReportDesignerController c, String elementId) async {
  c.select(elementId);
  await tester.pumpAndSettle();
  await _openProperties(tester);
}

void main() {
  // SC-001: the three real published-total references no longer false-flag.

  testWidgets(
      'summary grandTotal SUM(\$F{customerTotal}) shows no unresolved hint '
      '(customerTotal is a published total on the customer rows)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await _selectAndInspect(tester, c, 'grandTotal');
    expect(find.text(_unresolvedMsg), findsNothing);
  });

  testWidgets(
      'customer footer customerTotal \$F{customerTotal} shows no unresolved hint',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await _selectAndInspect(tester, c, 'customerTotal');
    expect(find.text(_unresolvedMsg), findsNothing);
  });

  testWidgets(
      'lines footer orderTotalFooter \$F{orderTotal} shows no unresolved hint '
      '(the nested-scope footer is reachable + resolves its published total)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await _selectAndInspect(tester, c, 'orderTotalFooter');
    expect(find.text(_unresolvedMsg), findsNothing);
  });

  // SC-002: a genuine typo still flags (no false negative).
  testWidgets('a genuine typo \$F{bogus} in the summary total still flags',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.setBinding('grandTotal', r'$F{bogus}');
    await _selectAndInspect(tester, c, 'grandTotal');
    expect(find.text(_unresolvedMsg), findsOneWidget);
  });

  // SC-005 (P2): the summary value picker lists the published total.
  testWidgets('the summary value picker offers customerTotal',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await _selectAndInspect(tester, c, 'grandTotal');

    await tester.tap(find.byKey(_valuePickKey));
    await tester.pumpAndSettle();
    expect(_valuePickItem('customerTotal'), findsOneWidget);
  });
}
