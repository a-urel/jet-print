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
}
