// Clipboard discoverability / localization / accessibility (016 / US3 / C4).
//
// Across en/de/tr: the three toolbar tooltips and five context-menu labels
// resolve to non-empty, locale-correct strings with no missing-key fallback
// (SC-004); every toolbar button and menu item exposes a Semantics label
// (FR-015); and the platform shortcut glyph is correct (⌘ on Apple, Ctrl+
// otherwise) in both the toolbar tooltips and the menu trailing (FR-014/014a).
//
// Locales are exercised in the order en → tr → de: the SDK's Global*
// localizations (pulled in by ShadApp) leak CLDR state across a `de`-then-`tr`
// transition within one test isolate (a documented framework quirk, see
// support/designer_harness.dart), so `tr` must never run immediately after `de`.
// The platform-glyph tests are registered first so they run before any `de`
// pump.
//
// VM-only: all three tests either exercise right-click (kSecondaryButton)
// gesture simulation (unsupported in headless Chrome at the test-harness level)
// or rely on debugDefaultTargetPlatformOverride to detect the platform glyph.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

// Toolbar keys.
const Key _tbCut = ValueKey<String>('jet_print.designer.action.cut');
const Key _tbCopy = ValueKey<String>('jet_print.designer.action.copy');
const Key _tbPaste = ValueKey<String>('jet_print.designer.action.paste');
// Menu keys.
const Key _mCut = ValueKey<String>('jet_print.designer.menu.cut');
const Key _mCopy = ValueKey<String>('jet_print.designer.menu.copy');
const Key _mPaste = ValueKey<String>('jet_print.designer.menu.paste');
const Key _mDuplicate = ValueKey<String>('jet_print.designer.menu.duplicate');
const Key _mDelete = ValueKey<String>('jet_print.designer.menu.delete');

// Expected localized labels per locale: [cut, copy, paste, duplicate, delete].
// Ordered en → tr → de (see the file header for why the order matters).
const List<MapEntry<String, List<String>>> _locales =
    <MapEntry<String, List<String>>>[
  MapEntry<String, List<String>>(
      'en', <String>['Cut', 'Copy', 'Paste', 'Duplicate', 'Delete']),
  MapEntry<String, List<String>>(
      'tr', <String>['Kes', 'Kopyala', 'Yapıştır', 'Çoğalt', 'Sil']),
  MapEntry<String, List<String>>('de', <String>[
    'Ausschneiden',
    'Kopieren',
    'Einfügen',
    'Duplizieren',
    'Löschen'
  ]),
];

ReportDefinition _fixture() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'a',
                    bounds: JetRect(x: 20, y: 20, width: 80, height: 24),
                    text: 'a'),
              ],
            )),
          ],
        ),
      ),
    );

Future<JetReportDesignerController> _pump(WidgetTester tester,
    {Locale? locale}) async {
  final JetReportDesignerController c = JetReportDesignerController()
    ..open(_fixture());
  await pumpDesignerWith(tester, controller: c, locale: locale);
  return c;
}

/// Opens the canvas context menu on element 'a' (which becomes selected).
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tapAt(
      tester.getCenter(
          find.byKey(const ValueKey<String>('jet_print.designer.element.a'))),
      buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  // --- Platform glyph tests (registered first; pump only `en`). ---

  testWidgets('shortcut glyph is ⌘ on Apple platforms', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final JetReportDesignerController c = await _pump(tester);
    c.select('a');
    await tester.pumpAndSettle();
    await _openMenu(tester);

    final String tbCut = tester.getSemantics(find.byKey(_tbCut)).label;
    final bool menuHasCmd = find.text('⌘X').evaluate().isNotEmpty &&
        find.text('⌘C').evaluate().isNotEmpty &&
        find.text('⌘V').evaluate().isNotEmpty &&
        find.text('⌘D').evaluate().isNotEmpty;
    debugDefaultTargetPlatformOverride = null;

    expect(tbCut, contains('⌘X')); // toolbar tooltip (FR-014)
    expect(menuHasCmd, isTrue); // menu trailing (FR-014a)
    expect(find.text('Ctrl+X'), findsNothing);
  });

  testWidgets('shortcut glyph is Ctrl+ on non-Apple platforms', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final JetReportDesignerController c = await _pump(tester);
    c.select('a');
    await tester.pumpAndSettle();
    await _openMenu(tester);

    final String tbCut = tester.getSemantics(find.byKey(_tbCut)).label;
    final bool menuHasCtrl = find.text('Ctrl+X').evaluate().isNotEmpty &&
        find.text('Ctrl+C').evaluate().isNotEmpty &&
        find.text('Ctrl+V').evaluate().isNotEmpty &&
        find.text('Ctrl+D').evaluate().isNotEmpty;
    debugDefaultTargetPlatformOverride = null;

    expect(tbCut, contains('Ctrl+X'));
    expect(menuHasCtrl, isTrue);
    expect(find.text('⌘X'), findsNothing);
  });

  // --- Per-locale localization + accessibility. ---
  //
  // All locales are exercised in ONE test with sequential pumps: the Global*
  // CLDR leak (see the file header) corrupts the SECOND non-English locale pumped
  // across separate tests, but a single test's sequential pumps load cleanly
  // (the same approach the top-bar overflow test uses).
  testWidgets('toolbar + context-menu labels are localized and accessible',
      (WidgetTester tester) async {
    const List<Key> menuKeys = <Key>[
      _mCut,
      _mCopy,
      _mPaste,
      _mDuplicate,
      _mDelete
    ];

    for (final MapEntry<String, List<String>> entry in _locales) {
      final String code = entry.key;
      final List<String> labels = entry.value;

      final JetReportDesignerController c =
          await _pump(tester, locale: Locale(code));
      c.select('a');
      await tester.pumpAndSettle();

      // Toolbar: each button's accessible name carries the localized label (the
      // shortcut glyph is appended after it) — FR-015, SC-004. A missing key
      // would fall back to English and fail the per-locale `contains`.
      expect(tester.getSemantics(find.byKey(_tbCut)).label,
          allOf(isNotEmpty, contains(labels[0])),
          reason: 'toolbar Cut tooltip in $code');
      expect(
          tester.getSemantics(find.byKey(_tbCopy)).label, contains(labels[1]),
          reason: 'toolbar Copy tooltip in $code');
      expect(
          tester.getSemantics(find.byKey(_tbPaste)).label, contains(labels[2]),
          reason: 'toolbar Paste tooltip in $code');

      // Context menu: each item renders its locale-correct label and exposes it
      // as an accessible name (find by semantics, scoped to the item) — FR-015.
      await _openMenu(tester);
      for (int i = 0; i < labels.length; i++) {
        expect(
            find.descendant(
                of: find.byKey(menuKeys[i]), matching: find.text(labels[i])),
            findsOneWidget,
            reason: 'menu item ${labels[i]} must render in $code');
        expect(
            find.descendant(
                of: find.byKey(menuKeys[i]),
                matching: find.bySemanticsLabel(RegExp(labels[i]))),
            findsWidgets,
            reason:
                'menu item ${labels[i]} must expose a semantics label in $code');
      }
    }
  });
}
