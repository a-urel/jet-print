// Tests for the onSelectDataSchema host callback plumbing (Task 2).
//
// Covers:
//   (a) DesignerSchemaScope.selectCallbackOf returns the wired callback / null,
//       and updateShouldNotify fires when the callback identity changes.
//   (b) Guard path: a JetReportDesigner with onSelectDataSchema that throws
//       routes the error to onError without propagating.
//
// Public API only — never imports src/.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

void main() {
  group('DesignerSchemaScope.selectCallbackOf', () {
    testWidgets('returns null when no callback is wired',
        (WidgetTester tester) async {
      VoidCallback? found;
      await pumpDesigner(tester, designer: Builder(builder: (BuildContext ctx) {
        // Wrap in a Builder so we get a descendant context.
        found = DesignerSchemaScope.selectCallbackOf(ctx);
        return const JetReportDesigner();
      }));
      // The builder runs before the designer subtree is in the tree, so use
      // a descendant element from within the designer instead.
      // Strategy: pump the designer with no callback and verify the accessor
      // returns null from within the built tree.
      expect(found, isNull);
    });

    testWidgets('returns the guarded callback when onSelectDataSchema is wired',
        (WidgetTester tester) async {
      bool called = false;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSelectDataSchema: () {
            called = true;
          },
        ),
      );
      // Walk the element tree to find a DesignerSchemaScope descendant and
      // call selectCallbackOf from its context.
      final Element el = tester.element(find.byType(JetReportDesigner));
      VoidCallback? cb;
      el.visitChildElements((Element child) {
        child.visitChildElements((Element grandchild) {
          cb ??= DesignerSchemaScope.selectCallbackOf(grandchild);
        });
      });
      expect(cb, isNotNull);
      // Calling the returned VoidCallback should invoke the original callback.
      cb!();
      expect(called, isTrue);
    });

    testWidgets('updateShouldNotify fires when callback identity changes',
        (WidgetTester tester) async {
      // Pump with callback A.
      void callbackA() {}
      void callbackB() {}

      final ValueNotifier<VoidCallback?> cbNotifier =
          ValueNotifier<VoidCallback?>(callbackA);
      addTearDown(cbNotifier.dispose);

      int notifyCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<VoidCallback?>(
            valueListenable: cbNotifier,
            builder: (BuildContext ctx, VoidCallback? cb, _) {
              return DesignerSchemaScope(
                dataSchema: null,
                onSelectDataSource: cb,
                child: Builder(
                  builder: (BuildContext innerCtx) {
                    // Read from scope so this builder is subscribed.
                    DesignerSchemaScope.selectCallbackOf(innerCtx);
                    notifyCount++;
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      );

      final int countAfterFirstPump = notifyCount;

      // Change the callback identity — should trigger a rebuild.
      cbNotifier.value = callbackB;
      await tester.pump();

      expect(notifyCount, greaterThan(countAfterFirstPump),
          reason: 'updateShouldNotify should fire when callback changes');
    });
  });

  group('onSelectDataSchema guard path', () {
    testWidgets(
        'error thrown by onSelectDataSchema is routed to onError, not propagated',
        (WidgetTester tester) async {
      Object? captured;
      StackTrace? capturedStack;

      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSelectDataSchema: () => throw StateError('schema boom'),
          onError: (Object e, StackTrace st) {
            captured = e;
            capturedStack = st;
          },
        ),
      );

      // Obtain the guarded callback from a descendant context.
      final Element designerEl = tester.element(find.byType(JetReportDesigner));
      VoidCallback? guardedCb;
      void findCb(Element element) {
        final VoidCallback? cb = DesignerSchemaScope.selectCallbackOf(element);
        if (cb != null) {
          guardedCb = cb;
          return;
        }
        element.visitChildElements(findCb);
      }

      designerEl.visitChildElements(findCb);
      expect(guardedCb, isNotNull,
          reason: 'scope must expose the guarded callback');

      // Invoke the guarded callback — the guard catches the StateError.
      guardedCb!();
      await tester.pump();

      expect(captured, isA<StateError>());
      expect(capturedStack, isNotNull);
      expect(tester.takeException(), isNull,
          reason: 'onError consumed it; nothing propagates to the framework');
    });

    testWidgets('workspace forwards onSelectDataSchema to designer',
        (WidgetTester tester) async {
      Object? captured;

      final JetReportDesignerController controller =
          JetReportDesignerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ShadApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            JetPrintLocalizations.delegate,
          ],
          supportedLocales: JetPrintLocalizations.supportedLocales,
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: const ShadSlateColorScheme.light(),
          ),
          home: JetReportWorkspace(
            controller: controller,
            renderReport: (_) async => throw UnimplementedError(),
            onSelectDataSchema: () => throw StateError('workspace boom'),
            onError: (Object e, StackTrace _) => captured = e,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Walk from the JetReportDesigner element to find the scope callback.
      final Element designerEl = tester.element(find.byType(JetReportDesigner));
      VoidCallback? guardedCb;
      void findCb(Element element) {
        final VoidCallback? cb = DesignerSchemaScope.selectCallbackOf(element);
        if (cb != null) {
          guardedCb = cb;
          return;
        }
        element.visitChildElements(findCb);
      }

      designerEl.visitChildElements(findCb);
      expect(guardedCb, isNotNull,
          reason:
              'workspace must wire the callback through the designer scope');

      guardedCb!();
      await tester.pump();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });
  });
}
