import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

void main() {
  const codec = TextElementCodec();
  const b = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('default visible is omitted from JSON (back-compat)', () {
    const el = TextElement(id: 't', bounds: b, text: 'x');
    expect(codec.toJson(el).containsKey('visible'), isFalse);
  });

  test('non-default visible round-trips', () {
    const el = TextElement(
        id: 't',
        bounds: b,
        text: 'x',
        visible: BoolProperty(value: false, expression: r'$F{ok}'));
    final json = codec.toJson(el);
    expect(json['visible'],
        <String, Object?>{'value': false, 'expression': r'$F{ok}'});
    expect(codec.fromJson(json).visible,
        const BoolProperty(value: false, expression: r'$F{ok}'));
  });

  test('legacy JSON without visible decodes to default', () {
    final el = codec.fromJson(<String, Object?>{
      'id': 't',
      'bounds': b.toJson(),
      'text': 'x',
    });
    expect(el.visible, const BoolProperty());
  });
}
