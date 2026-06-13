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

  // --- 018: editable page properties add exactly three public symbols — the
  // undoable controller mutator setPageFormat and copyWith on the two already-
  // public immutable value types. The paper/margin presets, recognition, clamp,
  // and the SetPageFormatCommand all stay private (not reachable from here).

  test('PageFormat.copyWith and JetEdgeInsets.copyWith are public (018)', () {
    const PageFormat base = PageFormat.a4Portrait;
    final PageFormat letter = base.copyWith(width: 612, height: 792).copyWith(
          margins: const JetEdgeInsets.all(14.17).copyWith(left: 50),
        );
    expect(letter.width, 612);
    expect(letter.margins.left, 50);
    expect(letter.margins.right, 14.17);
  });

  test('JetReportDesignerController.setPageFormat is the additive 018 mutator',
      () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    final PageFormat before = controller.template.page;
    controller.setPageFormat(
        before.copyWith(width: before.height, height: before.width));
    expect(controller.template.page.width, before.height);
    // Undoable in a single step, like every other edit.
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.template.page, before);
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

  // --- 020: the shape gallery adds exactly: six additive ShapeKind values, an
  // optional unknownForm field + copyWith on the already-public ShapeElement,
  // and the undoable controller mutator setShapeKind. shapePath, the
  // SetShapeKindCommand, and the _ShapeGallery widget stay private (a `src/`
  // import would be needed to reach them — this file never takes one).

  test('the six new ShapeKind forms are public and additive (020)', () {
    expect(
        ShapeKind.values,
        containsAll(<ShapeKind>[
          ShapeKind.line,
          ShapeKind.rectangle,
          ShapeKind.ellipse,
          ShapeKind.triangle,
          ShapeKind.diamond,
          ShapeKind.pentagon,
          ShapeKind.hexagon,
          ShapeKind.star,
        ]));
    // line/rectangle stay first so pre-feature wire values are unchanged.
    expect(ShapeKind.values.first, ShapeKind.line);
    expect(ShapeKind.values[1], ShapeKind.rectangle);
  });

  test('ShapeElement exposes copyWith and the unknownForm field (020)', () {
    const ShapeElement base = ShapeElement(
      id: 's',
      bounds: JetRect(x: 0, y: 0, width: 20, height: 20),
      kind: ShapeKind.rectangle,
    );
    final ShapeElement star = base.copyWith(kind: ShapeKind.star);
    expect(star.kind, ShapeKind.star);
    expect(star.bounds, base.bounds);
    expect(base.unknownForm, isNull);
    // The explicit clear flag is reachable from the public surface.
    const ShapeElement unknown = ShapeElement(
      id: 's',
      bounds: JetRect(x: 0, y: 0, width: 20, height: 20),
      kind: ShapeKind.rectangle,
      unknownForm: 'octagon',
    );
    expect(unknown.copyWith(clearUnknownForm: true).unknownForm, isNull);
  });

  test('JetReportDesignerController.setShapeKind is the additive 020 mutator',
      () {
    final JetReportDesignerController controller = JetReportDesignerController(
      template: const ReportTemplate(
        name: 'Shape',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                ShapeElement(
                  id: 's1',
                  bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
                  kind: ShapeKind.rectangle,
                ),
              ]),
        ],
      ),
    );
    controller.setShapeKind('s1', ShapeKind.hexagon);
    final ShapeElement shape =
        controller.template.bands.first.elements.first as ShapeElement;
    expect(shape.kind, ShapeKind.hexagon);
    // Undoable in a single step, like every other edit.
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(
      (controller.template.bands.first.elements.first as ShapeElement).kind,
      ShapeKind.rectangle,
    );
    controller.dispose();
  });

  // --- 021: format properties — the additions ride already-public types:
  // JetTextStyle.underline + copyWith, JetBoxStyle.copyWith, and the three
  // style mutators on the controller. `lib/jet_print.dart` needs NO new export
  // line, and the designer's FontRegistry stays internal: it is deliberately
  // absent from the export list (research §1 — a designer-only font seam would
  // silently break preview/export WYSIWYG), so it cannot even be named here. ---

  test('JetTextStyle exposes underline and a sentinel-based copyWith (021)',
      () {
    const JetTextStyle base =
        JetTextStyle(fontFamily: 'Inter', underline: true);
    expect(base.underline, isTrue);
    // Omitting fontFamily preserves it; explicit null clears it.
    expect(base.copyWith(fontSize: 9).fontFamily, 'Inter');
    expect(base.copyWith(fontFamily: null).fontFamily, isNull);
    expect(base.copyWith(underline: false).underline, isFalse);
  });

  test('JetReportDesignerController.setTextStyle restyles a text element (021)',
      () {
    final JetReportDesignerController controller = JetReportDesignerController(
      template: const ReportTemplate(
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
                ),
              ]),
        ],
      ),
    );
    controller.setTextStyle(
        't1',
        const JetTextStyle()
            .copyWith(weight: JetFontWeight.bold, underline: true));
    final TextElement text =
        controller.template.bands.first.elements.first as TextElement;
    expect(text.style.weight, JetFontWeight.bold);
    expect(text.style.underline, isTrue);
    // Undoable in a single step, like every other edit.
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(
      (controller.template.bands.first.elements.first as TextElement)
          .style
          .underline,
      isFalse,
    );
    controller.dispose();
  });

  test('JetBoxStyle exposes a sentinel-based copyWith (021)', () {
    const JetBoxStyle base = JetBoxStyle(
        fill: JetColor(0x3300FF00), stroke: JetColor.black, strokeWidth: 2);
    // Omitting preserves; explicit null clears (None states, FR-007/FR-008).
    expect(base.copyWith(strokeWidth: 5).fill, base.fill);
    expect(base.copyWith(fill: null).fill, isNull);
    expect(base.copyWith(stroke: null).stroke, isNull);
  });

  test('JetReportDesignerController.setShapeStyle restyles a shape (021)', () {
    final JetReportDesignerController controller = JetReportDesignerController(
      template: const ReportTemplate(
        name: 'API check',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                ShapeElement(
                  id: 's1',
                  bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
                  kind: ShapeKind.rectangle,
                  style: JetBoxStyle(stroke: JetColor.black),
                ),
              ]),
        ],
      ),
    );
    controller.setShapeStyle(
        's1',
        const JetBoxStyle(stroke: JetColor.black)
            .copyWith(fill: const JetColor(0x3300FF00), strokeWidth: 3));
    final ShapeElement shape =
        controller.template.bands.first.elements.first as ShapeElement;
    expect(shape.style.fill, const JetColor(0x3300FF00));
    expect(shape.style.strokeWidth, 3);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(
      (controller.template.bands.first.elements.first as ShapeElement)
          .style
          .fill,
      isNull,
    );
    controller.dispose();
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
