// Public-API import test (US1 / SC-001 / SC-007).
//
// Acts as an external consumer: it imports ONLY the single public entry point
// and proves the documented surface (JetPrintPlaceholder, jetPrintVersion,
// JetReportDesigner, JetPrintLocalizations) is reachable and sufficient. If this
// file ever needs a `package:jet_print/src/` import to do its job, the public
// API is incomplete.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('jetPrintVersion is exposed as a non-empty String', () {
    expect(jetPrintVersion, isA<String>());
    expect(jetPrintVersion, isNotEmpty);
  });

  test('JetPrintPlaceholder is const-constructible and is a Widget', () {
    const placeholder = JetPrintPlaceholder();
    expect(placeholder, isA<Widget>());
  });

  test('JetReportDesigner is const-constructible and is a Widget', () {
    // The shell must require no host state / no required params (contract).
    const designer = JetReportDesigner();
    expect(designer, isA<Widget>());
  });

  test('JetPrintLocalizations exposes a delegate and supported locales', () {
    expect(
      JetPrintLocalizations.delegate,
      isA<LocalizationsDelegate<JetPrintLocalizations>>(),
    );
    // The library ships English (default/fallback), German and Turkish.
    final List<String> codes = JetPrintLocalizations.supportedLocales
        .map((Locale l) => l.languageCode)
        .toList();
    expect(codes, containsAll(<String>['en', 'de', 'tr']));
    // English is listed first so unsupported locales resolve to it (FR-017).
    expect(JetPrintLocalizations.supportedLocales.first.languageCode, 'en');
  });

  // --- 003: the model graph + controller + format are reachable and, together,
  // sufficient to build, mutate, and serialize a design (contracts §7.1). ---

  test('the model graph builds a ReportTemplate from the public surface', () {
    const ReportTemplate template = ReportTemplate(
      name: 'API check',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 80,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 0, y: 0, width: 100, height: 18),
              text: 'Hi',
              style: JetTextStyle(weight: JetFontWeight.bold),
            ),
            ShapeElement(
              id: 's1',
              bounds: JetRect(x: 0, y: 20, width: 100, height: 0),
              kind: ShapeKind.line,
              style: JetBoxStyle(stroke: JetColor.black),
            ),
          ],
        ),
      ],
    );
    expect(template.bands.single.elements.length, 2);
    // Geometry helpers are reachable.
    expect(template.bands.single.elements.first.bounds, isA<JetRect>());
  });

  test('JetReportDesignerController mutates the model and is undoable', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    final int before = controller.template.bands.first.elements.length;
    controller.createElement(
      DesignerToolType.text,
      bandIndex: 0,
      at: const JetOffset(10, 10),
    );
    expect(controller.template.bands.first.elements.length, before + 1);
    expect(controller.selection.isNotEmpty, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.template.bands.first.elements.length, before);
    controller.dispose();
  });

  test('the controller exposes canCopy / canPaste clipboard predicates (016)',
      () {
    // The two clipboard UI surfaces (toolbar + canvas context menu) bind their
    // enablement to these two getters, mirroring the existing canUndo/canRedo
    // idiom — a reviewed, additive public surface (Constitution I / FR-012).
    final JetReportDesignerController controller =
        JetReportDesignerController();
    // Empty document: nothing selected, nothing on the clipboard.
    expect(controller.canCopy, isFalse);
    expect(controller.canPaste, isFalse);

    controller.createElement(
      DesignerToolType.text,
      bandIndex: 0,
      at: const JetOffset(10, 10),
    );
    // The new element is auto-selected, so Cut/Copy become available.
    expect(controller.canCopy, isTrue);
    expect(controller.canPaste, isFalse);

    controller.copy();
    // A Copy fills the clipboard → Paste available; selection intact.
    expect(controller.canPaste, isTrue);
    controller.dispose();
  });

  test('JetReportFormat serializes a mutated design losslessly', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    controller.createElement(
      DesignerToolType.barcode,
      bandIndex: 0,
      at: const JetOffset(5, 5),
    );
    final String json = JetReportFormat.encodeJson(controller.template);
    final ReportTemplate reopened = JetReportFormat.decodeJson(json);
    expect(
      JetReportFormat.encode(reopened),
      equals(JetReportFormat.encode(controller.template)),
    );
    controller.dispose();
  });

  // --- 017: the unified toolbar adds exactly two public symbols — an undoable
  // controller mutator and an optional preview callback. The mode switch reuses
  // the already-public onPreviewRequested/onBack; everything else stays private.

  test('JetReportDesignerController.rename is the additive 017 mutator', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    controller.rename('Renamed report');
    expect(controller.template.name, 'Renamed report');
    // Undoable in a single step, like every other edit.
    controller.undo();
    expect(controller.template.name, '',
        reason: 'a fresh design starts with an empty (placeholder) name');
    controller.dispose();
  });

  test('JetReportPreview exposes the additive onRename callback (017)', () {
    final RenderedReport report = const JetReportEngine().render(
      const ReportTemplate(
        name: 'X',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[ReportBand(type: BandType.detail, height: 20)],
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );
    final JetReportPreview preview =
        JetReportPreview(report: report, onRename: (String _) {});
    expect(preview.onRename, isNotNull);
    expect(preview, isA<Widget>());
  });

  test('JetReportWorkspace is constructible from the public surface', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    addTearDown(controller.dispose);
    final JetReportWorkspace workspace = JetReportWorkspace(
      controller: controller,
      renderReport: (ReportTemplate t) => const JetReportEngine().render(
        t,
        JetInMemoryDataSource(const <Map<String, Object?>>[]),
      ),
    );
    expect(workspace, isA<Widget>());
  });
}
