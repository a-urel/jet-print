import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/layout/page_nav_control.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _toggle = ValueKey<String>('jet_print.preview.page.menuToggle');
const Key _first = ValueKey<String>('jet_print.preview.page.first');
const Key _last = ValueKey<String>('jet_print.preview.page.last');
const Key _goto = ValueKey<String>('jet_print.preview.page.gotoField');

Future<void> _pump(
  WidgetTester tester, {
  required int pageIndex,
  required int pageCount,
  required ValueChanged<int> onGoTo,
  String keyPrefix = 'jet_print.preview',
}) {
  return tester.pumpWidget(
    ShadApp(
      localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: Center(
        child: PageNavControl(
          pageIndex: pageIndex,
          pageCount: pageCount,
          onGoTo: onGoTo,
          keyPrefix: keyPrefix,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the current page as a localized "X of Y" indicator',
      (WidgetTester tester) async {
    await _pump(tester, pageIndex: 4, pageCount: 10, onGoTo: (_) {});
    expect(find.text('Page 5 of 10'), findsOneWidget);
  });

  testWidgets('tapping the indicator opens a menu with First / Last / Go to',
      (WidgetTester tester) async {
    await _pump(tester, pageIndex: 4, pageCount: 10, onGoTo: (_) {});
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(_first), findsOneWidget);
    expect(find.byKey(_last), findsOneWidget);
    expect(find.byKey(_goto), findsOneWidget);
  });

  testWidgets('picking First page reports index 0',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_first));
    await tester.pumpAndSettle();
    expect(got, 0);
  });

  testWidgets('picking Last page reports the final index',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_last));
    await tester.pumpAndSettle();
    expect(got, 9);
  });

  testWidgets('First page is disabled on the first page (tap is a no-op)',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 0, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_first));
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets('Last page is disabled on the last page (tap is a no-op)',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 9, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_last));
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets(
      'Go to page: submitting a 1-based number reports the 0-based index',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_goto), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(got, 6);
  });

  testWidgets('Go to page: an over-range number clamps to the last index',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_goto), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(got, 9);
  });

  testWidgets('Go to page: a sub-1 number clamps to the first index',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_goto), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(got, 0);
  });

  testWidgets('Go to page: a non-numeric entry reports nothing',
      (WidgetTester tester) async {
    int? got;
    await _pump(tester,
        pageIndex: 4, pageCount: 10, onGoTo: (int i) => got = i);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_goto), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets('keyPrefix namespaces every key', (WidgetTester tester) async {
    await _pump(tester,
        pageIndex: 4,
        pageCount: 10,
        onGoTo: (_) {},
        keyPrefix: 'jet_print.designer');
    expect(find.byKey(_toggle), findsNothing);
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.page.menuToggle')),
        findsOneWidget);
  });
}
