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
    test('deserializes integer-encoded JSON (real jsonDecode output)', () {
      expect(JetSize.fromJson(<String, Object?>{'w': 120, 'h': 48}),
          const JetSize(120, 48));
    });
    test('equal values share a hash code', () {
      expect(const JetSize(1, 2).hashCode, const JetSize(1, 2).hashCode);
    });
  });

  group('JetOffset', () {
    test('round-trips through JSON', () {
      const JetOffset offset = JetOffset(8, -4);
      expect(JetOffset.fromJson(offset.toJson()), offset);
    });
    test('has value equality and a consistent hash code', () {
      expect(const JetOffset(8, -4), const JetOffset(8, -4));
      expect(const JetOffset(8, -4).hashCode, const JetOffset(8, -4).hashCode);
      expect(const JetOffset(8, -4) == const JetOffset(-4, 8), isFalse);
    });
    test('deserializes integer-encoded JSON', () {
      expect(JetOffset.fromJson(<String, Object?>{'dx': 8, 'dy': -4}),
          const JetOffset(8, -4));
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
    test('has value equality and a consistent hash code', () {
      expect(const JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4).hashCode,
          const JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4).hashCode);
      expect(
          const JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4) ==
              const JetEdgeInsets(left: 4, top: 3, right: 2, bottom: 1),
          isFalse);
    });
    test('deserializes integer-encoded JSON', () {
      expect(
          JetEdgeInsets.fromJson(
              <String, Object?>{'l': 1, 't': 2, 'r': 3, 'b': 4}),
          const JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4));
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
    test('has value equality and a consistent hash code', () {
      expect(const JetRect(x: 10, y: 20, width: 100, height: 40).hashCode,
          const JetRect(x: 10, y: 20, width: 100, height: 40).hashCode);
      expect(
          const JetRect(x: 10, y: 20, width: 100, height: 40) ==
              const JetRect(x: 0, y: 0, width: 1, height: 1),
          isFalse);
    });
    test('deserializes integer-encoded JSON', () {
      expect(
          JetRect.fromJson(
              <String, Object?>{'x': 10, 'y': 20, 'w': 100, 'h': 40}),
          const JetRect(x: 10, y: 20, width: 100, height: 40));
    });
  });
}
