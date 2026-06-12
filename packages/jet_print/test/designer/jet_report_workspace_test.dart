// JetReportWorkspace widget tests: keep-alive switching + deferred render with
// loading feedback. Black-box through the public API only.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _modeDesignerKey =
    ValueKey<String>('jet_print.toolbar.mode.designer');
const Key _modePreviewKey = ValueKey<String>('jet_print.toolbar.mode.preview');
const Key _loadingKey = ValueKey<String>('jet_print.workspace.loading');
const Key _surfaceKey = ValueKey<String>('jet_print.designer.surface');
const Key _pageKey = ValueKey<String>('jet_print.preview.page');

ReportTemplate _template() => const ReportTemplate(
      name: 'Quarterly Report',
      page: _page,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
          ],
        ),
      ],
    );

RenderedReport _render(ReportTemplate t) => const JetReportEngine().render(
      t,
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Future<JetReportWorkspace> _pumpWorkspace(
  WidgetTester tester, {
  required JetReportDesignerController controller,
  ReportRenderCallback? renderReport,
  ValueChanged<RenderedReport>? onExportPdf,
  ValueChanged<RenderedReport>? onPrint,
  WidgetBuilder? loadingBuilder,
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final JetReportWorkspace workspace = JetReportWorkspace(
    controller: controller,
    renderReport: renderReport ?? _render,
    onExportPdf: onExportPdf,
    onPrint: onPrint,
    loadingBuilder: loadingBuilder,
  );
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: workspace,
  ));
  await tester.pump();
  return workspace;
}

/// Switches into preview from the designer and drives the deferred render to
/// completion. The loading bar (an indeterminate ShadProgress) forbids
/// pumpAndSettle until it is gone, so we pump explicit frames.
Future<void> _enterPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(_modePreviewKey));
  await tester.pump(); // mode → preview; loading shown; render scheduled
  await tester
      .pump(const Duration(milliseconds: 1)); // fire the zero-delay timer
  await tester.pumpAndSettle(); // report ready → preview records its page
}

void main() {
  testWidgets('starts in designer mode', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);

    expect(find.byKey(_surfaceKey), findsOneWidget);
    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.byKey(_pageKey), findsNothing);
  });

  testWidgets('entering preview shows the loading bar, then the rendered page',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);

    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pump(); // loading frame (render deferred by one frame)
    expect(find.byKey(_loadingKey), findsOneWidget,
        reason: 'the loading bar is visible while the first render runs');
    expect(find.byKey(_pageKey), findsNothing);

    await tester.pump(const Duration(milliseconds: 1)); // run the render
    await tester.pumpAndSettle(); // preview records its page
    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('switching back to design is instant and keeps the canvas alive',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(tester, controller: controller);
    await _enterPreview(tester);

    // While in preview the designer surface is still mounted (offstage), proving
    // it was never torn down.
    expect(find.byKey(_surfaceKey, skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump(); // single frame — no re-record, no async gap
    expect(find.byKey(_surfaceKey), findsOneWidget);
    expect(find.byKey(_loadingKey), findsNothing);
  });

  testWidgets('an unedited round trip into preview reuses the report',
      (WidgetTester tester) async {
    int renders = 0;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) {
        renders++;
        return _render(t);
      },
    );

    await _enterPreview(tester);
    expect(renders, 1);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pumpAndSettle(); // no render scheduled → safe to settle
    expect(renders, 1, reason: 'unchanged template ⇒ cached report reused');
    expect(find.byKey(_pageKey), findsOneWidget);
  });

  testWidgets('editing the template re-renders on the next preview entry',
      (WidgetTester tester) async {
    int renders = 0;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) {
        renders++;
        return _render(t);
      },
    );

    await _enterPreview(tester);
    expect(renders, 1);

    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    // Edit: rename produces a NEW immutable template (identity changes).
    controller.rename('Edited');
    await tester.pump();
    await _enterPreview(tester);
    expect(renders, 2, reason: 'changed template ⇒ a fresh render');
  });

  testWidgets('a failed render reports the error and clears the spinner',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) => throw StateError('render failed'),
    );

    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pump(); // loading shown; render scheduled
    expect(find.byKey(_loadingKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1)); // render runs → throws
    // The failure is reported via FlutterError.reportError (not an uncaught
    // zone error); consume it so the test does not fail on the expected error.
    expect(tester.takeException(), isStateError);
    // The spinner is cleared (not stuck) and switching back still works.
    expect(find.byKey(_loadingKey), findsNothing);
    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    expect(find.byKey(_surfaceKey), findsOneWidget);
  });

  testWidgets('export and print fire with the current rendered report',
      (WidgetTester tester) async {
    RenderedReport? exported;
    RenderedReport? printed;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      onExportPdf: (RenderedReport r) => exported = r,
      onPrint: (RenderedReport r) => printed = r,
    );
    await _enterPreview(tester);

    await tester
        .tap(find.byKey(const ValueKey<String>('jet_print.preview.export')));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey<String>('jet_print.preview.print')));
    await tester.pump();

    expect(exported, isNotNull);
    expect(printed, same(exported),
        reason: 'both actions act on the single current rendered report');
    expect(exported!.pageCount, 3);
  });

  testWidgets(
      'a re-render keeps the old pages visible with an overlay until it completes',
      (WidgetTester tester) async {
    final List<Completer<RenderedReport>> gates = <Completer<RenderedReport>>[];
    int calls = 0;
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) {
        calls++;
        if (calls == 1) return _render(t); // first render resolves immediately
        final Completer<RenderedReport> gate = Completer<RenderedReport>();
        gates.add(gate);
        return gate.future; // second render is gated open
      },
    );

    await _enterPreview(tester); // first render → page shown
    expect(find.text('Quarterly Report'), findsOneWidget);

    // Edit (new template identity) and re-enter preview: the second render is
    // gated, so it stays in flight.
    await tester.tap(find.byKey(_modeDesignerKey));
    await tester.pump();
    controller.rename('Edited');
    await tester.pump();
    await tester.tap(find.byKey(_modePreviewKey));
    await tester
        .pump(); // mode preview; _rendering true; old report still shown
    await tester
        .pump(const Duration(milliseconds: 1)); // fire timer → gated render

    // The OLD pages remain visible (no blank flash) under a loading overlay.
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(find.text('Quarterly Report'), findsOneWidget,
        reason: 'old report stays visible while the re-render is in flight');
    expect(find.byKey(_loadingKey), findsOneWidget,
        reason: 'an overlay indicator shows the re-render is running');

    // Complete the gated render → the new pages replace the old ones.
    gates.single.complete(_render(controller.template));
    await tester.pumpAndSettle();
    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets('loadingBuilder overrides the default indicator',
      (WidgetTester tester) async {
    const Key customKey = ValueKey<String>('custom.loading');
    final Completer<RenderedReport> gate = Completer<RenderedReport>();
    final JetReportDesignerController controller =
        JetReportDesignerController(template: _template());
    addTearDown(controller.dispose);
    await _pumpWorkspace(
      tester,
      controller: controller,
      renderReport: (ReportTemplate t) => gate.future, // gated open
      loadingBuilder: (BuildContext context) =>
          const SizedBox(key: customKey, height: 4),
    );

    await tester.tap(find.byKey(_modePreviewKey));
    await tester.pump(); // loading shown via the custom builder
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(customKey), findsOneWidget,
        reason: 'the custom loadingBuilder replaces the default bar');
    expect(find.byKey(_loadingKey), findsNothing,
        reason: 'the default ShadProgress bar is not used when overridden');

    // Complete the render so nothing is left pending.
    gate.complete(_render(controller.template));
    await tester.pumpAndSettle();
  });
}
