import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

void main() {
  group('UnknownElement', () {
    test('is a ReportElement that reports the original type key', () {
      final UnknownElement element = UnknownElement(
        typeKey: 'sparkline',
        rawJson: <String, Object?>{
          'type': 'sparkline',
          'id': 'spark1',
          'bounds': <String, Object?>{'x': 1, 'y': 2, 'w': 30, 'h': 10},
          'series': <Object?>[1, 2, 3],
        },
      );
      expect(element, isA<ReportElement>());
      expect(element.typeKey, 'sparkline');
      expect(element.id, 'spark1');
      expect(element.bounds, const JetRect(x: 1, y: 2, width: 30, height: 10));
    });

    test('falls back to empty id and zero bounds when absent', () {
      final UnknownElement element = UnknownElement(
        typeKey: 'mystery',
        rawJson: <String, Object?>{'type': 'mystery'},
      );
      expect(element.id, '');
      expect(element.bounds, JetRect.zero);
    });
  });
}
