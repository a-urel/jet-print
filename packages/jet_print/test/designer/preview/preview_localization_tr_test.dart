// Preview chrome localization — Turkish (011 — C11 / FR-017). One isolate per
// non-English locale (see preview_localization_support.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_localization_support.dart';

void main() {
  testWidgets('Turkish chrome', (WidgetTester tester) async {
    await pumpLocalizedPreview(tester, const Locale('tr'), withActions: true);
    expect(find.text('Sayfa 1 / 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Önceki sayfa'), findsOneWidget);
    expect(find.bySemanticsLabel('Sonraki sayfa'), findsOneWidget);
    expect(find.bySemanticsLabel('Genişliğe sığdır'), findsOneWidget);
    // 012 export/print actions (FR-014).
    expect(find.bySemanticsLabel('PDF olarak dışa aktar'), findsOneWidget);
    expect(find.bySemanticsLabel('Yazdır'), findsOneWidget);
  });
}
