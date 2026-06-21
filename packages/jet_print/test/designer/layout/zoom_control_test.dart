import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/layout/zoom_control.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _toggle = ValueKey<String>('jet_print.designer.zoom.menuToggle');
const Key _field = ValueKey<String>('jet_print.designer.action.zoomLevel');
const Key _fitPage = ValueKey<String>('jet_print.designer.zoom.fitPage');
const Key _fitWidth = ValueKey<String>('jet_print.designer.zoom.fitWidth');
const Key _preset200 = ValueKey<String>('jet_print.designer.zoom.preset.200');

Future<void> _pump(
  WidgetTester tester, {
  required double viewScale,
  required JetViewFitMode fitMode,
  required ValueChanged<double> onPercent,
  required ValueChanged<JetViewFitMode> onFit,
  String keyPrefix = 'jet_print.designer',
}) {
  return tester.pumpWidget(
    ShadApp(
      localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: Center(
        child: ZoomControl(
          viewScale: viewScale,
          fitMode: fitMode,
          onPercent: onPercent,
          onFit: onFit,
          keyPrefix: keyPrefix,
        ),
      ),
    ),
  );
}

/// The percentage shown on the bar trigger (the always-visible label).
String _triggerText(WidgetTester tester) => tester
    .widget<Text>(
        find.descendant(of: find.byKey(_toggle), matching: find.byType(Text)))
    .data!;

/// The text inside the in-popup editable field (menu must be open).
String _fieldText(WidgetTester tester) =>
    tester.widget<ShadInput>(find.byKey(_field)).controller!.text;

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_toggle));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bar shows the current scale as a label, not an input',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 0.87,
        fitMode: JetViewFitMode.width,
        onPercent: (_) {},
        onFit: (_) {});
    expect(_triggerText(tester), '87%');
    // The editable field lives in the popup; it is absent until the menu opens.
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('opening the menu reveals the field, fit modes, and presets',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    await _open(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(_fitWidth), findsOneWidget);
    expect(find.byKey(_fitPage), findsOneWidget);
    expect(find.byKey(_preset200), findsOneWidget);
  });

  testWidgets('the in-popup field opens showing the current scale',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 0.87,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    await _open(tester);
    expect(_fieldText(tester), '87%');
  });

  testWidgets('typing a value in the popup field and submitting reports it',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});
    await _open(tester);
    await tester.enterText(find.byKey(_field), '130');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(got, 130);
  });

  testWidgets('an invalid entry reverts without reporting',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});
    await _open(tester);
    await tester.enterText(find.byKey(_field), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(got, isNull);
    expect(_fieldText(tester), '100%'); // reverted to the current value
  });

  testWidgets('a trailing % in the typed value is tolerated',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});
    await _open(tester);
    await tester.enterText(find.byKey(_field), '150%');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(got, 150);
  });

  testWidgets('opening the menu and picking Fit page reports the fit mode',
      (WidgetTester tester) async {
    JetViewFitMode? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (JetViewFitMode m) => got = m);
    await _open(tester);
    await tester.tap(find.byKey(_fitPage));
    await tester.pumpAndSettle();
    expect(got, JetViewFitMode.page);
  });

  testWidgets('Fit width row calls onFit(width)', (WidgetTester tester) async {
    JetViewFitMode? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (JetViewFitMode m) => got = m);
    await _open(tester);
    await tester.tap(find.byKey(_fitWidth));
    await tester.pumpAndSettle();
    expect(got, JetViewFitMode.width);
  });

  testWidgets('picking a preset reports the percent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});
    await _open(tester);
    await tester.tap(find.byKey(_preset200));
    await tester.pumpAndSettle();
    expect(got, 200);
  });

  testWidgets('active fit mode shows a checkmark; inactive rows do not',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.width,
        onPercent: (_) {},
        onFit: (_) {});
    await _open(tester);

    Icon iconIn(Finder row) => tester
        .widgetList<Icon>(find.descendant(of: row, matching: find.byType(Icon)))
        .firstWhere((Icon i) => i.icon == LucideIcons.check);

    final Icon widthIcon = iconIn(find.byKey(_fitWidth));
    final Icon pageIcon = iconIn(find.byKey(_fitPage));
    expect(widthIcon.icon, LucideIcons.check);
    expect(pageIcon.icon, LucideIcons.check);
    // The selected row's check is a visible colour; the unselected one is hidden
    // (coloured as the background), so the two must differ.
    expect(widthIcon.color, isNot(equals(pageIcon.color)));
  });

  testWidgets('the bar label syncs when the scale changes (didUpdateWidget)',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    expect(_triggerText(tester), '100%');

    await _pump(tester,
        viewScale: 2.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    await tester.pump();
    expect(_triggerText(tester), '200%');
  });

  testWidgets('keyPrefix namespaces every key (default stays designer)',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    expect(find.byKey(_toggle), findsOneWidget); // jet_print.designer.*

    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {},
        keyPrefix: 'jet_print.preview');
    expect(find.byKey(_toggle), findsNothing);
    await tester.tap(find
        .byKey(const ValueKey<String>('jet_print.preview.zoom.menuToggle')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.preview.action.zoomLevel')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('jet_print.preview.zoom.fitWidth')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('jet_print.preview.zoom.preset.200')),
        findsOneWidget);
  });
}
