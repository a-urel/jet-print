// packages/jet_print/test/domain/watermark_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';

void main() {
  group('Watermark', () {
    test('defaults: opacity 0.15, angle -45, contain', () {
      const wm = Watermark(text: 'DRAFT');
      expect(wm.opacity, 0.15);
      expect(wm.angleDegrees, -45);
      expect(wm.imageFit, JetBoxFit.contain);
      expect(wm.textStyle, JetTextStyle.fallback);
      expect(wm.imageBytes, isNull);
    });

    test('opacity is clamped to 0..1', () {
      expect(const Watermark(text: 'x', opacity: 5).opacity, 1.0);
      expect(const Watermark(text: 'x', opacity: -1).opacity, 0.0);
    });

    test('value equality (text variant)', () {
      const a = Watermark(text: 'DRAFT', angleDegrees: -30);
      const b = Watermark(text: 'DRAFT', angleDegrees: -30);
      const c = Watermark(text: 'DRAFT', angleDegrees: 0);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('value equality compares image bytes', () {
      final a = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
      final b = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
      final c = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 9]));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces only named fields', () {
      const a = Watermark(text: 'DRAFT', opacity: 0.2);
      expect(a.copyWith(opacity: 0.5).opacity, 0.5);
      expect(a.copyWith(opacity: 0.5).text, 'DRAFT');
    });

    test('JSON round-trips the text variant', () {
      const a = Watermark(
          text: 'CONFIDENTIAL',
          opacity: 0.2,
          angleDegrees: -30,
          textStyle: JetTextStyle(fontSize: 72));
      expect(Watermark.fromJson(a.toJson()), a);
    });

    test('JSON round-trips the image variant', () {
      final a = Watermark(
          imageBytes: Uint8List.fromList(<int>[10, 20, 30, 40]),
          imageFit: JetBoxFit.cover,
          opacity: 0.1);
      expect(Watermark.fromJson(a.toJson()), a);
    });
  });
}
