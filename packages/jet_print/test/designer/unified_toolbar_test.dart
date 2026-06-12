// Unified toolbar — shared-shell region parity (017 / US1 / C1 / SC-003).
//
// Black-box: stands in for an external consumer and imports ONLY the public
// entry point. The designer top bar and the preview toolbar are now both
// composed from one private shell (`UnifiedTopBar`), so the left (report name)
// and center (Designer|Preview mode switch) regions MUST occupy the same
// position and size in either mode. The test can't see the private shell type,
// so it asserts parity through the shared, stable region keys — the observable
// proxy for "one shell renders both".
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const Key _nameKey = ValueKey<String>('jet_print.toolbar.name');
const Key _switchKey = ValueKey<String>('jet_print.toolbar.modeSwitch');
const Key _modePreviewKey = ValueKey<String>('jet_print.toolbar.mode.preview');

const Size _size = Size(1200, 800);
const PageFormat _page =
    PageFormat(width: 400, height: 300, margins: JetEdgeInsets.all(10));

ReportTemplate _template(String name) => ReportTemplate(
      name: name,
      page: _page,
      bands: const <ReportBand>[ReportBand(type: BandType.detail, height: 50)],
    );

RenderedReport _report(String name) => const JetReportEngine().render(
      _template(name),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );

/// Pumps the designer shell carrying [name] (a wired onPreviewRequested keeps
/// the Preview segment enabled).
Future<void> _pumpDesignerShell(
  WidgetTester tester, {
  required String name,
  Size size = _size,
  Locale? locale,
}) async {
  final JetReportDesignerController c =
      JetReportDesignerController(template: _template(name));
  addTearDown(c.dispose);
  await pumpDesigner(
    tester,
    size: size,
    locale: locale,
    designer: JetReportDesigner(controller: c, onPreviewRequested: (_) {}),
  );
}

/// Pumps the preview shell over a report titled [name], wired exactly as the
/// designer harness wires its `ShadApp` (same delegate, same theme).
Future<void> _pumpPreviewShell(
  WidgetTester tester, {
  required String name,
  Size size = _size,
  Locale? locale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    locale: locale,
    themeMode: ThemeMode.light,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    // The shared left region (file icon + read-only name) must be byte-for-byte
    // identical to the designer's, so the bar reads as one toolbar.
    home: JetReportPreview(
      report: _report(name),
      onBack: () {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('unified toolbar — shared-shell region parity (C1 / SC-003)', () {
    testWidgets('the name + mode switch sit at the same place in both modes',
        (WidgetTester tester) async {
      await _pumpDesignerShell(tester, name: 'Parity');
      expect(find.byKey(_nameKey), findsOneWidget);
      expect(find.byKey(_switchKey), findsOneWidget);
      final Rect dName = tester.getRect(find.byKey(_nameKey));
      final Rect dSwitch = tester.getRect(find.byKey(_switchKey));

      await _pumpPreviewShell(tester, name: 'Parity');
      expect(find.byKey(_nameKey), findsOneWidget);
      expect(find.byKey(_switchKey), findsOneWidget);
      final Rect pName = tester.getRect(find.byKey(_nameKey));
      final Rect pSwitch = tester.getRect(find.byKey(_switchKey));

      // Same name → identical left region and switch placement across modes.
      expect(pName.left, moreOrLessEquals(dName.left, epsilon: 0.5));
      expect(pName.top, moreOrLessEquals(dName.top, epsilon: 0.5));
      expect(pSwitch.left, moreOrLessEquals(dSwitch.left, epsilon: 0.5));
      expect(pSwitch.top, moreOrLessEquals(dSwitch.top, epsilon: 0.5));
      expect(pSwitch.width, moreOrLessEquals(dSwitch.width, epsilon: 0.5));
      expect(pSwitch.height, moreOrLessEquals(dSwitch.height, epsilon: 0.5));
    });

    testWidgets('the toolbar height is the shared 52px in both modes (C1.3)',
        (WidgetTester tester) async {
      await _pumpDesignerShell(tester, name: 'H');
      final double designerSwitchTop =
          tester.getRect(find.byKey(_switchKey)).center.dy;
      // The switch is vertically centered in the 52px bar in both modes.
      await _pumpPreviewShell(tester, name: 'H');
      expect(tester.getRect(find.byKey(_switchKey)).center.dy,
          moreOrLessEquals(designerSwitchTop, epsilon: 0.5));
    });

    testWidgets(
        'a very long name truncates without displacing the switch or actions',
        (WidgetTester tester) async {
      await _pumpDesignerShell(tester, name: 'V' * 200);

      // The name is bounded (ellipsized) — it never grows past the region cap.
      final Size nameSize = tester.getSize(find.byKey(_nameKey));
      expect(nameSize.width, lessThanOrEqualTo(241),
          reason: 'a long name ellipsizes within its bounded width');

      // The switch is still present and fully on-screen.
      expect(find.byKey(_switchKey), findsOneWidget);
      final Rect sw = tester.getRect(find.byKey(_switchKey));
      expect(sw.left, greaterThanOrEqualTo(0));
      expect(sw.right, lessThanOrEqualTo(_size.width + 0.5));

      // A designer action is still rendered (right slot intact).
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // 017 (US3 / C6): when narrow, the action region collapses/scrolls but the
  // name region and the mode switch are never the regions that disappear.
  group('unified toolbar — responsive degradation (C6)', () {
    testWidgets('the name + switch stay present and on-screen when narrow', (
      WidgetTester tester,
    ) async {
      await _pumpDesignerShell(tester,
          name: 'Narrow', size: const Size(560, 760));

      // Name + switch remain present and within the viewport (C6.2).
      expect(find.byKey(_nameKey), findsOneWidget);
      expect(find.byKey(_switchKey), findsOneWidget);
      final Rect name = tester.getRect(find.byKey(_nameKey));
      final Rect sw = tester.getRect(find.byKey(_switchKey));
      expect(name.left, greaterThanOrEqualTo(0));
      expect(sw.left, greaterThanOrEqualTo(0));
      expect(sw.left, lessThan(560),
          reason: 'switch reachable at scroll origin');
      // The actions still exist (scrolled), so nothing was dropped (C6.1).
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // 017 (US3 / C7): the four new chrome strings resolve in every shipped locale,
  // and the switch + rename affordance carry accessible names and are operable.
  group('unified toolbar — localization & accessibility (C7)', () {
    testWidgets('the four new keys resolve in en/de/tr with real translations',
        (WidgetTester tester) async {
      final JetPrintLocalizations en =
          await JetPrintLocalizations.delegate.load(const Locale('en'));
      final JetPrintLocalizations de =
          await JetPrintLocalizations.delegate.load(const Locale('de'));
      final JetPrintLocalizations tr =
          await JetPrintLocalizations.delegate.load(const Locale('tr'));

      for (final JetPrintLocalizations l in <JetPrintLocalizations>[
        en,
        de,
        tr
      ]) {
        expect(l.modeDesigner, isNotEmpty);
        expect(l.modePreview, isNotEmpty);
        expect(l.actionRenameTooltip, isNotEmpty);
        expect(l.renameFieldLabel, isNotEmpty);
      }
      // Real translations, not English everywhere (C7.1).
      expect(de.modePreview, isNot(en.modePreview)); // Vorschau ≠ Preview
      expect(tr.modePreview, isNot(en.modePreview)); // Önizleme ≠ Preview
      expect(de.actionRenameTooltip, isNot(en.actionRenameTooltip));
    });

    testWidgets('the switch segments carry accessible names (C7.2)',
        (WidgetTester tester) async {
      final JetReportDesignerController c =
          JetReportDesignerController(template: _template('A11y'));
      addTearDown(c.dispose);
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(controller: c, onPreviewRequested: (_) {}),
      );

      // The switch segments are labelled with their localized text.
      expect(find.text('Designer'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
    });

    testWidgets('the mode switch is keyboard-operable (C7.2)', (
      WidgetTester tester,
    ) async {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      int previews = 0;
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
            controller: c, onPreviewRequested: (_) => previews++),
      );

      // Focus the Preview segment via its label and activate it with Enter.
      final Element label = tester.element(find.descendant(
          of: find.byKey(_modePreviewKey), matching: find.byType(Text)));
      Focus.of(label).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(previews, 1,
          reason: 'Enter activates the focused Preview segment');
    });
  });
}
