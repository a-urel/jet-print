// Rendering seam test (SC-004).
//
// White-box test of the rendering placeholder type. It depends on the domain
// type (proving the inward dependency direction works) and imports no designer
// code. Like the domain test, it imports the private `src` path because it
// tests the library's own internals.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/domain.dart';
import 'package:jet_print/src/rendering/rendering.dart';

void main() {
  group('ReportLayout (rendering seam)', () {
    test('lays out one page per document section', () {
      const ReportDocument doc = ReportDocument(
        title: 'Report',
        sections: <String>['a', 'b', 'c'],
      );
      const ReportLayout layout = ReportLayout(doc);
      expect(layout.document, same(doc));
      expect(layout.pageCount, 3);
    });

    test('an empty document still yields a single page', () {
      const ReportDocument doc = ReportDocument(title: 'Report');
      const ReportLayout layout = ReportLayout(doc);
      expect(layout.pageCount, 1);
    });
  });
}
