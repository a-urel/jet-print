// Tests for the onSelectDataSchema host callback plumbing (Task 2).
//
// Covers:
//   (a) DesignerSchemaScope.selectCallbackOf returns the wired callback / null,
//       and updateShouldNotify fires when the callback identity changes.
//   (b) Guard path: a JetReportDesigner with onSelectDataSchema that throws
//       routes the error to onError without propagating.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/designer_schema_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

void main() {
  group('DesignerSchemaScope.selectCallbackOf', () {
    testWidgets('returns null when no callback is wired',
        (WidgetTester tester) async {
      // Pump the designer with no onSelectDataSchema (default).
      await pumpDesigner(tester, designer: const JetReportDesigner());

      // Walk the element tree from the JetReportDesigner to find the first
      // descendant context that sits inside the DesignerSchemaScope, then
      // assert selectCallbackOf returns null from there.
      final Element el = tester.element(find.byType(JetReportDesigner));
      VoidCallback? result;
      bool scopeSeen = false;
      void walk(Element element) {
        if (scopeSeen) return;
        if (element.getInheritedWidgetOfExactType<DesignerSchemaScope>() !=
            null) {
          scopeSeen = true;
          result = DesignerSchemaScope.selectCallbackOf(element);
          return;
        }
        element.visitChildElements(walk);
      }

      el.visitChildElements(walk);
      expect(scopeSeen, isTrue,
          reason:
              'DesignerSchemaScope must be present in the designer subtree');
      expect(result, isNull,
          reason: 'no onSelectDataSchema was wired — callback must be null');
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

  group('DataSourcePanel select button', () {
    Future<void> pumpSelectWorkspace(
      WidgetTester tester, {
      VoidCallback? onSelectDataSchema,
      JetDataSchema? dataSchema,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final JetReportDesignerController controller =
          JetReportDesignerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(ShadApp(
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
          onSelectDataSchema: onSelectDataSchema,
          dataSchema: dataSchema,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'empty panel + wired callback shows the button and tapping invokes it',
        (WidgetTester tester) async {
      int taps = 0;
      await pumpSelectWorkspace(tester, onSelectDataSchema: () => taps++);

      // Data Source is the default-active tab — no navigation needed.
      final Finder button = find.byKey(
          const ValueKey<String>('jet_print.dataSource.selectButton'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('empty panel without a wired callback shows no button',
        (WidgetTester tester) async {
      await pumpSelectWorkspace(tester);

      // No callback wired → just the empty-state hint, no select button.
      expect(
          find.byKey(
              const ValueKey<String>('jet_print.dataSource.selectButton')),
          findsNothing);
    });

    testWidgets('schema attached → dataset tree, no button',
        (WidgetTester tester) async {
      await pumpSelectWorkspace(
        tester,
        onSelectDataSchema: () {},
        dataSchema: const JetDataSchema(
          name: 'TestSchema',
          fields: <FieldDef>[
            FieldDef('amount', type: JetFieldType.double),
          ],
        ),
      );

      // Schema present → tree shown, button absent.
      expect(find.text('TestSchema'), findsOneWidget);
      expect(
          find.byKey(
              const ValueKey<String>('jet_print.dataSource.selectButton')),
          findsNothing);
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
