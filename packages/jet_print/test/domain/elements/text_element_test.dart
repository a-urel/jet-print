import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';

void main() {
  group('TextElement', () {
    const TextElement element = TextElement(
      id: 'title',
      bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
      text: 'Invoice',
    );

    test('is a ReportElement with the "text" type key', () {
      expect(element, isA<ReportElement>());
      expect(element.typeKey, 'text');
    });

    test('exposes id, bounds, and text', () {
      expect(element.id, 'title');
      expect(element.bounds, const JetRect(x: 0, y: 0, width: 200, height: 24));
      expect(element.text, 'Invoice');
    });

    test('has value equality', () {
      expect(
        element,
        const TextElement(
          id: 'title',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
          text: 'Invoice',
        ),
      );
      expect(
          element ==
              const TextElement(
                id: 'title',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
                text: 'Different',
              ),
          isFalse);
    });
  });
}
