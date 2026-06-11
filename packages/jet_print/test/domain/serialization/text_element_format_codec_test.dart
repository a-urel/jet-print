// TextElement.format serialization (013 / T019): additive, optional, no schema
// bump. Absent ⇒ null; written only when set; round-trips exactly.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

const JetRect _r = JetRect(x: 1, y: 2, width: 3, height: 4);
const TextElementCodec _codec = TextElementCodec();

void main() {
  test('format is written only when set', () {
    const TextElement withFmt =
        TextElement(id: 't', bounds: _r, text: 'x', format: '#,##0.00');
    expect(_codec.toJson(withFmt)['format'], '#,##0.00');

    const TextElement noFmt = TextElement(id: 't', bounds: _r, text: 'x');
    expect(_codec.toJson(noFmt).containsKey('format'), isFalse);
  });

  test('round-trips with a format', () {
    const TextElement el = TextElement(
        id: 't',
        bounds: _r,
        text: 'x',
        expression: r'$F{amount}',
        format: '#,##0.00');
    expect(_codec.fromJson(_codec.toJson(el)), el);
  });

  test('a payload with no format decodes to null (backward compatible)', () {
    final TextElement decoded = _codec.fromJson(<String, Object?>{
      'id': 't',
      'bounds': _r.toJson(),
      'text': 'x',
    });
    expect(decoded.format, isNull);
  });
}
