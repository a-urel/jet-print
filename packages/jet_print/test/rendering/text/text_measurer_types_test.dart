// test/rendering/text/text_measurer_types_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  test('TextLine has value equality and a readable toString', () {
    const TextLine a = TextLine(
        text: 'Hi', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const TextLine b = TextLine(
        text: 'Hi', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const TextLine c = TextLine(
        text: 'Ho', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.toString(), 'TextLine("Hi", w: 6.39, top: 0.0, base: 10.69)');
  });

  test('MeasuredText carries lines, size, and firstAscent', () {
    const TextLine l = TextLine(
        text: 'A', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const MeasuredText m = MeasuredText(
        lines: <TextLine>[l], size: JetSize(6.39, 13.62), firstAscent: 10.69);
    expect(m.lines.single, l);
    expect(m.size, const JetSize(6.39, 13.62));
    expect(m.firstAscent, 10.69);
  });
}
