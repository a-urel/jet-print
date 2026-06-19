import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart' show JetPrintLocalizations;

void main() {
  for (final Locale locale in <Locale>[
    const Locale('en'),
    const Locale('de'),
    const Locale('tr'),
  ]) {
    testWidgets('zoom chrome strings resolve for $locale',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: JetPrintLocalizations.localizationsDelegates,
          child: Builder(
            builder: (BuildContext context) {
              final JetPrintLocalizations l10n =
                  JetPrintLocalizations.of(context);
              expect(l10n.actionZoomFieldTooltip, isNotEmpty);
              expect(l10n.menuZoomFitWidth, isNotEmpty);
              expect(l10n.menuZoomFitPage, isNotEmpty);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  }
}
