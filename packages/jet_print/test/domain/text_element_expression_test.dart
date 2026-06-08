// TextElement.expression (007b): optional data-binding source; codec round-trips it.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 5);

  test('expression defaults to null and is part of value equality', () {
    const TextElement a = TextElement(id: 't', bounds: r, text: 'x');
    expect(a.expression, isNull);
    const TextElement b =
        TextElement(id: 't', bounds: r, text: 'x', expression: r'$F{name}');
    expect(a, isNot(b));
    expect(b.expression, r'$F{name}');
  });

  test('codec omits expression when null, round-trips it when present', () {
    const TextElementCodec codec = TextElementCodec();
    const TextElement plain = TextElement(id: 't', bounds: r, text: 'x');
    expect(codec.toJson(plain).containsKey('expression'), isFalse);

    const TextElement bound =
        TextElement(id: 't', bounds: r, text: '', expression: r'$F{name}');
    final Map<String, Object?> json = codec.toJson(bound);
    expect(json['expression'], r'$F{name}');
    expect(codec.fromJson(<String, Object?>{'type': 'text', ...json}), bound);
  });
}
