// Band captions ("Page Header", "Detail", "Group Header", …) sit in a column
// to the LEFT of the page, never on it. A caption is wider than many reports'
// left margin (~70px for "Group Header", ~100px for the Turkish "Sütun Alt
// Bilgisi" against an invoice's 28pt margin), so drawn on the page it covered
// the first element of its band.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/designer_harness.dart';

const List<String> _defaultBands = <String>[
  'pageHeader',
  'detail',
  'pageFooter'
];

Finder _caption(String bandId) =>
    find.byKey(ValueKey<String>('jet_print.designer.bandBadge.$bandId'));

void _expectCaptionsBesideThePage(WidgetTester tester) {
  final Rect page = tester.getRect(find.byKey(kDesignPageKey));
  for (final String band in _defaultBands) {
    final Finder caption = _caption(band);
    expect(caption, findsOneWidget, reason: band);
    final Rect r = tester.getRect(caption);
    // The canvas viewport: the scroll view the caption scrolls inside.
    final Rect viewport = tester.getRect(find
        .ancestor(of: caption, matching: find.byType(SingleChildScrollView))
        .first);
    expect(r.right, lessThanOrEqualTo(page.left),
        reason: '$band caption must not reach onto the page');
    expect(r.left, greaterThanOrEqualTo(viewport.left),
        reason: '$band caption must stay inside the visible canvas');
  }
}

void main() {
  testWidgets('band captions sit beside the page, not on it',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);
    _expectCaptionsBesideThePage(tester);
  });

  testWidgets('the longest (Turkish) captions still fit beside the page',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester, locale: const Locale('tr'));
    _expectCaptionsBesideThePage(tester);
  });

  testWidgets('captions stay beside the page in a narrow window',
      (WidgetTester tester) async {
    // Fit-to-width: the page fills the canvas, so the caption column has to be
    // reserved by the fit, not just left over.
    await pumpDesignerWith(tester, size: const Size(1100, 800));
    _expectCaptionsBesideThePage(tester);
  });
}
