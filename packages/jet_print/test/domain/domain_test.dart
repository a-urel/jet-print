// Domain seam test (SC-004).
//
// Exercises the domain placeholder type in isolation. This is a white-box test
// of the library's own internals, so it imports the private `src` path directly
// (allowed for the package's own tests; external consumers may not — see
// encapsulation_test.dart). It intentionally imports NO Flutter UI library,
// demonstrating the domain seam is pure Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/domain.dart';

void main() {
  group('ReportDocument (domain seam)', () {
    test('exposes its title and sections', () {
      const ReportDocument doc = ReportDocument(
        title: 'Q3 Report',
        sections: <String>['Summary', 'Detail'],
      );
      expect(doc.title, 'Q3 Report');
      expect(doc.sections, <String>['Summary', 'Detail']);
      expect(doc.isEmpty, isFalse);
    });

    test('defaults to having no sections', () {
      const ReportDocument doc = ReportDocument(title: 'Blank');
      expect(doc.sections, isEmpty);
      expect(doc.isEmpty, isTrue);
    });
  });
}
