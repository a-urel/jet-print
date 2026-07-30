// The thumbnail-toggle strings exist in every supported locale (FR-016/FR-017).
// Black-box: reads the strings through the public localization delegate.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// Pumps a minimal localized host under [locale] and returns the resolved
/// strings.
Future<JetPrintLocalizations> _load(WidgetTester tester, Locale locale) async {
  late JetPrintLocalizations l10n;
  await tester.pumpWidget(WidgetsApp(
    color: const Color(0xFF000000),
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
        PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) =>
          builder(context),
    ),
    home: Builder(
      builder: (BuildContext context) {
        l10n = JetPrintLocalizations.of(context);
        return const SizedBox.shrink();
      },
    ),
  ));
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  testWidgets('the thumbnail-toggle strings resolve in en/de/tr', (
    WidgetTester tester,
  ) async {
    for (final Locale locale in <Locale>[
      const Locale('en'),
      const Locale('de'),
      const Locale('tr'),
    ]) {
      final JetPrintLocalizations l10n = await _load(tester, locale);
      expect(l10n.previewShowThumbnails, isNotEmpty, reason: '$locale show');
      expect(l10n.previewHideThumbnails, isNotEmpty, reason: '$locale hide');
      expect(l10n.previewShowThumbnails, isNot(l10n.previewHideThumbnails),
          reason: '$locale show/hide must differ');
    }
  });
}
