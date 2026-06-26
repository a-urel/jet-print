import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);
  const TextElementCodec codec = TextElementCodec();

  test('text element name round-trips when set', () {
    const TextElement t =
        TextElement(id: 't', bounds: r, text: 'hi', name: 'Greeting');
    final Map<String, Object?> json = codec.toJson(t);
    expect(json['name'], 'Greeting');
    expect(codec.fromJson(json).name, 'Greeting');
  });

  test('text element omits name key when null (byte-compatible legacy)', () {
    const TextElement t = TextElement(id: 't', bounds: r, text: 'hi');
    final Map<String, Object?> json = codec.toJson(t);
    expect(json.containsKey('name'), isFalse);
  });

  test('legacy JSON without name decodes to null', () {
    final TextElement decoded = codec.fromJson(<String, Object?>{
      'id': 't',
      'bounds': r.toJson(),
      'text': 'hi',
    });
    expect(decoded.name, isNull);
  });
}
