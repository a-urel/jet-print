// Public-API import test (US1 / SC-001 / SC-007; spec 024 / C13).
//
// Acts as an external consumer: it imports ONLY the single public entry point
// and proves the documented surface is reachable and sufficient to build,
// mutate, validate, serialize, and render a report — now expressed in the
// reified [ReportDefinition] model. The legacy ReportTemplate/ReportBand/
// ReportGroup graph is gone; this file no longer needs (or names) it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/test_fonts.dart';

/// A minimal reified definition: the master scope with one detail band carrying
/// [elements].
ReportDefinition _detailDef({
  List<ReportElement> elements = const <ReportElement>[],
}) =>
    ReportDefinition(
      name: 'API check',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 80,
                elements: elements)),
          ],
        ),
      ),
    );

/// The first element of the master detail band — the reified replacement for
/// `template.bands.first.elements.first`.
ReportElement _firstElement(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements
        .first;

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
    final List<String> codes = JetPrintLocalizations.supportedLocales
        .map((Locale l) => l.languageCode)
        .toList();
    expect(codes, containsAll(<String>['en', 'de', 'tr']));
    expect(JetPrintLocalizations.supportedLocales.first.languageCode, 'en');
  });

  // --- 024: the reified model graph is the public surface. The tree types are
  // reachable and, together with the controller + format + validate, sufficient
  // to build, mutate, validate, and serialize a design (contracts §7.1 / C13). ---

  test(
      'the reified tree types build a ReportDefinition from the public surface',
      () {
    const ReportDefinition def = ReportDefinition(
      name: 'API check',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(id: 'ph', type: BandType.pageHeader, height: 24),
      ),
      body: ReportBody(
        title: Band(id: 'title', type: BandType.title, height: 20),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'g1',
              name: 'category',
              key: r'$F{category}',
              header: Band(id: 'gh', type: BandType.groupHeader, height: 18),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                TextElement(
                  id: 't1',
                  bounds: JetRect(x: 0, y: 0, width: 100, height: 18),
                  text: 'Hi',
                  style: JetTextStyle(weight: JetFontWeight.bold),
                ),
              ],
            )),
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(id: 'line', type: BandType.detail, height: 16)),
              ],
            )),
          ],
        ),
      ),
    );
    expect(def.furniture.pageHeader, isA<Band>());
    expect(def.body.root.groups.single, isA<GroupLevel>());
    expect(def.body.root.children.whereType<NestedScope>().single.scope.id,
        'lines');
    // The sealed ScopeNode is matchable from the public surface.
    final ScopeNode node = def.body.root.children.first;
    expect(node, isA<BandNode>());
  });

  test('validate() is public and returns Diagnostics for the reified model',
      () {
    // A clean definition yields no errors; a duplicate group name is flagged.
    expect(
      validate(_detailDef())
          .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
      isEmpty,
    );
    const ReportDefinition dup = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'dup', key: r'$F{a}'),
            GroupLevel(id: 'g2', name: 'dup', key: r'$F{b}'),
          ],
        ),
      ),
    );
    expect(
      validate(dup)
          .any((Diagnostic d) => d.severity == DiagnosticSeverity.error),
      isTrue,
    );
  });

  test('JetReportDesignerController mutates the model and is undoable', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    final int before = controller.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements
        .length;
    controller.createElement(
      DesignerToolType.text,
      bandId: 'detail',
      at: const JetOffset(10, 10),
    );
    expect(_firstElement(controller), isA<TextElement>());
    expect(controller.selection.isNotEmpty, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(
      controller.definition.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .length,
      before,
    );
    controller.dispose();
  });

  test('the controller exposes first-class group & scope mutators (024)', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    // Create a group on the master scope, select it, and toggle a flag — each
    // an undoable step keyed by the group's stable id.
    controller.createGroup('root', name: 'cat', key: r'$F{cat}');
    final GroupLevel group = controller.definition.body.root.groups.single;
    controller.selectGroup(group.id);
    expect(controller.selection.groupId, group.id);
    controller.setGroupStartNewPage(group.id, true);
    expect(controller.definition.body.root.groups.single.startNewPage, isTrue);
    // Nested scopes are first-class too.
    controller.createScope('root', collectionField: 'lines');
    expect(controller.definition.body.root.children.whereType<NestedScope>(),
        hasLength(1));
    // Author-time diagnostics surface through the controller.
    expect(controller.diagnostics, isA<List<Diagnostic>>());
    controller.dispose();
  });

  test('the controller exposes canCopy / canPaste clipboard predicates (016)',
      () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    expect(controller.canCopy, isFalse);
    expect(controller.canPaste, isFalse);
    controller.createElement(
      DesignerToolType.text,
      bandId: 'detail',
      at: const JetOffset(10, 10),
    );
    expect(controller.canCopy, isTrue);
    expect(controller.canPaste, isFalse);
    controller.copy();
    expect(controller.canPaste, isTrue);
    controller.dispose();
  });

  test('JetReportFormat serializes a mutated design losslessly (v2)', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    controller.createElement(
      DesignerToolType.barcode,
      bandId: 'detail',
      at: const JetOffset(5, 5),
    );
    final String json =
        JetReportFormat.encodeDefinitionJson(controller.definition);
    final ReportDefinition reopened =
        JetReportFormat.decodeDefinitionJson(json);
    expect(
      JetReportFormat.encodeDefinition(reopened),
      equals(JetReportFormat.encodeDefinition(controller.definition)),
    );
    controller.dispose();
  });

  test('JetReportDesignerController.rename is the additive 017 mutator', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    controller.rename('Renamed report');
    expect(controller.definition.name, 'Renamed report');
    controller.undo();
    expect(controller.definition.name, '',
        reason: 'a fresh design starts with an empty (placeholder) name');
    controller.dispose();
  });

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
    final PageFormat before = controller.definition.page;
    controller.setPageFormat(
        before.copyWith(width: before.height, height: before.width));
    expect(controller.definition.page.width, before.height);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.definition.page, before);
    controller.dispose();
  });

  test('JetReportPreview exposes the additive onRename callback (017)', () {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _flatTextDef(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );
    final JetReportPreview preview =
        JetReportPreview(report: report, onRename: (String _) {});
    expect(preview.onRename, isNotNull);
    expect(preview, isA<Widget>());
  });

  test('the eight ShapeKind forms are public and additive (020)', () {
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
      definition: _detailDef(elements: const <ReportElement>[
        ShapeElement(
          id: 's1',
          bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
          kind: ShapeKind.rectangle,
        ),
      ]),
    );
    controller.setShapeKind('s1', ShapeKind.hexagon);
    expect((_firstElement(controller) as ShapeElement).kind, ShapeKind.hexagon);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(
        (_firstElement(controller) as ShapeElement).kind, ShapeKind.rectangle);
    controller.dispose();
  });

  test('JetTextStyle exposes underline and a sentinel-based copyWith (021)',
      () {
    const JetTextStyle base =
        JetTextStyle(fontFamily: 'Inter', underline: true);
    expect(base.underline, isTrue);
    expect(base.copyWith(fontSize: 9).fontFamily, 'Inter');
    expect(base.copyWith(fontFamily: null).fontFamily, isNull);
    expect(base.copyWith(underline: false).underline, isFalse);
  });

  test('JetReportDesignerController.setTextStyle restyles a text element (021)',
      () {
    final JetReportDesignerController controller = JetReportDesignerController(
      definition: _detailDef(elements: const <ReportElement>[
        TextElement(
          id: 't1',
          bounds: JetRect(x: 0, y: 0, width: 100, height: 18),
          text: 'Hi',
        ),
      ]),
    );
    controller.setTextStyle(
        't1',
        const JetTextStyle()
            .copyWith(weight: JetFontWeight.bold, underline: true));
    final TextElement text = _firstElement(controller) as TextElement;
    expect(text.style.weight, JetFontWeight.bold);
    expect(text.style.underline, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect((_firstElement(controller) as TextElement).style.underline, isFalse);
    controller.dispose();
  });

  test('JetBoxStyle exposes a sentinel-based copyWith (021)', () {
    const JetBoxStyle base = JetBoxStyle(
        fill: JetColor(0x3300FF00), stroke: JetColor.black, strokeWidth: 2);
    expect(base.copyWith(strokeWidth: 5).fill, base.fill);
    expect(base.copyWith(fill: null).fill, isNull);
    expect(base.copyWith(stroke: null).stroke, isNull);
  });

  test('JetReportDesignerController.setShapeStyle restyles a shape (021)', () {
    final JetReportDesignerController controller = JetReportDesignerController(
      definition: _detailDef(elements: const <ReportElement>[
        ShapeElement(
          id: 's1',
          bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
          kind: ShapeKind.rectangle,
          style: JetBoxStyle(stroke: JetColor.black),
        ),
      ]),
    );
    controller.setShapeStyle(
        's1',
        const JetBoxStyle(stroke: JetColor.black)
            .copyWith(fill: const JetColor(0x3300FF00), strokeWidth: 3));
    final ShapeElement shape = _firstElement(controller) as ShapeElement;
    expect(shape.style.fill, const JetColor(0x3300FF00));
    expect(shape.style.strokeWidth, 3);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect((_firstElement(controller) as ShapeElement).style.fill, isNull);
    controller.dispose();
  });

  test('JetReportDesignerController.setBarcodeColor recolors a barcode (021)',
      () {
    final JetReportDesignerController controller = JetReportDesignerController(
      definition: _detailDef(elements: const <ReportElement>[
        BarcodeElement(
          id: 'b1',
          bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
          symbology: BarcodeSymbology.qrCode,
          data: '42',
        ),
      ]),
    );
    controller.setBarcodeColor('b1', const JetColor(0xFF1E40AF));
    expect((_firstElement(controller) as BarcodeElement).color,
        const JetColor(0xFF1E40AF));
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect((_firstElement(controller) as BarcodeElement).color, JetColor.black);
    controller.dispose();
  });

  test('JetReportWorkspace is constructible from the public surface', () {
    final JetReportDesignerController controller =
        JetReportDesignerController();
    addTearDown(controller.dispose);
    final JetReportWorkspace workspace = JetReportWorkspace(
      controller: controller,
      renderReport: (ReportDefinition d) => const JetReportEngine()
          .renderDefinition(
              d, JetInMemoryDataSource(const <Map<String, Object?>>[])),
    );
    expect(workspace, isA<Widget>());
  });

  test('JetFontFace / JetFontFamily are exported and validate eagerly (022)',
      () {
    final JetFontFace face = JetFontFace(bytes: validRegularFontBytes());
    expect(face.weight, JetFontWeight.normal);
    expect(face.italic, isFalse);
    final JetFontFamily family =
        JetFontFamily(name: 'Acme Brand', faces: <JetFontFace>[face]);
    expect(family.name, 'Acme Brand');
    expect(
      () => JetFontFamily(
          name: 'Bad',
          faces: <JetFontFace>[JetFontFace(bytes: malformedFontBytes())]),
      throwsA(isA<FontFormatException>()),
    );
  });

  test('RenderOptions.fonts is an additive field defaulting to empty (022)',
      () {
    expect(const RenderOptions().fonts, isEmpty);
    final RenderOptions withFonts = RenderOptions(fonts: <JetFontFamily>[
      JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())]),
    ]);
    expect(withFonts.fonts, hasLength(1));
  });

  test('JetReportDesigner and JetReportWorkspace accept a fonts param (022)',
      () {
    final List<JetFontFamily> fonts = <JetFontFamily>[
      JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())]),
    ];
    expect(JetReportDesigner(fonts: fonts, showBuiltInFonts: false),
        isA<Widget>());
    final JetReportDesignerController controller =
        JetReportDesignerController();
    addTearDown(controller.dispose);
    expect(
      JetReportWorkspace(
        controller: controller,
        fonts: fonts,
        showBuiltInFonts: false,
        renderReport: (ReportDefinition d) => const JetReportEngine()
            .renderDefinition(
                d, JetInMemoryDataSource(const <Map<String, Object?>>[])),
      ),
      isA<Widget>(),
    );
  });
}

/// A one-band reified definition with a single text element — for the preview
/// render test.
ReportDefinition _flatTextDef() => const ReportDefinition(
      name: 'X',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 20)),
          ],
        ),
      ),
    );
