// Host-callback hardening: onError catches failures the host raised inside the
// Save/Open/Preview callbacks (sync throw or rejected Future). Drives the public
// JetReportDesigner only; never reaches into src/.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

// The Preview mode-switch segment key (mirrors unified_top_bar.dart).
const Key _previewSegment = ValueKey<String>('jet_print.toolbar.mode.preview');

void main() {
  group('JetReportDesigner onError', () {
    testWidgets('catches a synchronous throw from onSaveRequested',
        (WidgetTester tester) async {
      Object? captured;
      StackTrace? capturedStack;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) =>
              throw StateError('boom save'),
          onError: (Object e, StackTrace st) {
            captured = e;
            capturedStack = st;
          },
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(captured, isA<StateError>());
      expect(capturedStack, isNotNull);
      expect(tester.takeException(), isNull,
          reason: 'onError consumed it; nothing propagates');
    });

    testWidgets('catches an async rejection from onOpenRequested',
        (WidgetTester tester) async {
      Object? captured;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: () async => throw StateError('boom open'),
          onError: (Object e, StackTrace _) => captured = e,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('routes a Preview failure through onError',
        (WidgetTester tester) async {
      Object? captured;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onPreviewRequested: (ReportDefinition _) =>
              throw StateError('boom preview'),
          onError: (Object e, StackTrace _) => captured = e,
        ),
      );

      await tester.tap(find.byKey(_previewSegment));
      await tester.pumpAndSettle();

      expect(captured, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no onError a host throw propagates (not swallowed)',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) => throw StateError('boom'),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(tester.takeException(), isA<StateError>(),
          reason: 'no sink wired ⇒ error surfaces, never silently dropped');
    });
  });

  group('Open/Save button visibility', () {
    testWidgets('both absent when no file callbacks are wired',
        (WidgetTester tester) async {
      await pumpDesigner(tester); // const JetReportDesigner(), no callbacks
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(LucideIcons.folderOpen), findsNothing);
      expect(find.byIcon(LucideIcons.save), findsNothing);
    });

    testWidgets('both present when both callbacks are wired',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: () {},
          onSaveRequested: (ReportDefinition _) {},
        ),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('only Save shows when only onSaveRequested is wired',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onSaveRequested: (ReportDefinition _) {},
        ),
      );
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });
  });
}
