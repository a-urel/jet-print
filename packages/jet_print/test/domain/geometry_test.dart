// Pure-Dart geometry value types (spec 003). No Flutter UI import — proving the
// domain seam stays headless.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  group('JetSize', () {
    test('round-trips through JSON', () {
      const JetSize size = JetSize(120, 48);
      expect(JetSize.fromJson(size.toJson()), size);
    });
    test('has value equality', () {
      expect(const JetSize(1, 2), const JetSize(1, 2));
      expect(const JetSize(1, 2) == const JetSize(2, 1), isFalse);
    });
  });

  group('JetOffset', () {
    test('round-trips through JSON', () {
      const JetOffset offset = JetOffset(8, -4);
      expect(JetOffset.fromJson(offset.toJson()), offset);
    });
  });

  group('JetEdgeInsets', () {
    test('round-trips through JSON', () {
      const JetEdgeInsets insets =
          JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4);
      expect(JetEdgeInsets.fromJson(insets.toJson()), insets);
    });
    test('.all sets every side equal', () {
      expect(const JetEdgeInsets.all(5),
          const JetEdgeInsets(left: 5, top: 5, right: 5, bottom: 5));
    });
  });

  group('JetRect', () {
    test('round-trips through JSON', () {
      const JetRect rect = JetRect(x: 10, y: 20, width: 100, height: 40);
      expect(JetRect.fromJson(rect.toJson()), rect);
    });
    test('exposes zero as the empty rect', () {
      expect(JetRect.zero, const JetRect(x: 0, y: 0, width: 0, height: 0));
    });
  });
}
