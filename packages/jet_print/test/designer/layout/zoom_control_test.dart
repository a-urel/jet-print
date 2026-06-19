import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/l10n/jet_print_localizations.dart';
import 'package:jet_print/src/designer/layout/zoom_control.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _field = ValueKey<String>('jet_print.designer.action.zoomLevel');
const Key _caret = ValueKey<String>('jet_print.designer.zoom.menuToggle');
const Key _fitPage = ValueKey<String>('jet_print.designer.zoom.fitPage');
const Key _fitWidth = ValueKey<String>('jet_print.designer.zoom.fitWidth');
const Key _preset200 = ValueKey<String>('jet_print.designer.zoom.preset.200');

Future<void> _pump(
  WidgetTester tester, {
  required double viewScale,
  required JetViewFitMode fitMode,
  required ValueChanged<double> onPercent,
  required ValueChanged<JetViewFitMode> onFit,
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
        ),
      ),
    ),
  );
}

String _fieldText(WidgetTester tester) =>
    tester.widget<ShadInput>(find.byKey(_field)).controller!.text;

void main() {
  testWidgets('shows the current scale as a rounded percentage',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 0.87,
        fitMode: JetViewFitMode.width,
        onPercent: (_) {},
        onFit: (_) {});
    expect(_fieldText(tester), '87%');
  });

  testWidgets('typing a value and submitting reports the percent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

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

    await tester.enterText(find.byKey(_field), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(got, isNull);
    expect(_fieldText(tester), '100%'); // reverted to the current value
  });

  testWidgets('opening the menu and picking Fit page reports the fit mode',
      (WidgetTester tester) async {
    JetViewFitMode? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (JetViewFitMode m) => got = m);

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_fitPage));
    await tester.pumpAndSettle();

    expect(got, JetViewFitMode.page);
  });

  testWidgets('picking a preset reports the percent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_preset200));
    await tester.pumpAndSettle();

    expect(got, 200);
  });

  testWidgets('blur after invalid entry does NOT fire onPercent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.enterText(find.byKey(_field), 'abc');
    // Blur the field without submitting — triggers the focus-change commit path.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(got, isNull);
    expect(_fieldText(tester), '100%');
  });

  testWidgets('a trailing % in the typed value is tolerated',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.enterText(find.byKey(_field), '150%');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(got, 150);
  });

  testWidgets('active fit mode shows a checkmark; inactive rows do not',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.width,
        onPercent: (_) {},
        onFit: (_) {});

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();

    // Both rows must render an Icon with LucideIcons.check (always present,
    // just coloured differently).
    final Finder fitWidthRow = find.byKey(_fitWidth);
    final Finder fitPageRow = find.byKey(_fitPage);

    Icon iconIn(Finder row) => tester
        .widgetList<Icon>(
            find.descendant(of: row, matching: find.byType(Icon)))
        .firstWhere((Icon i) => i.icon == LucideIcons.check);

    final Icon widthIcon = iconIn(fitWidthRow);
    final Icon pageIcon = iconIn(fitPageRow);

    // Both must carry a check glyph.
    expect(widthIcon.icon, LucideIcons.check);
    expect(pageIcon.icon, LucideIcons.check);

    // The selected row's check must be a different (visible) colour from the
    // unselected row's check (which is coloured as the background to hide it).
    expect(widthIcon.color, isNot(equals(pageIcon.color)));
  });

  testWidgets('Fit width row calls onFit(width)',
      (WidgetTester tester) async {
    JetViewFitMode? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (JetViewFitMode m) => got = m);

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_fitWidth));
    await tester.pumpAndSettle();

    expect(got, JetViewFitMode.width);
  });

  testWidgets('didUpdateWidget syncs the field when not focused',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});

    expect(_fieldText(tester), '100%');

    // Re-pump with a new viewScale while the field is not focused.
    await _pump(tester,
        viewScale: 2.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    await tester.pump();

    expect(_fieldText(tester), '200%');
  });
}
