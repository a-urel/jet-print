// JetConstraints: a max-width/height sizing bound for ElementRenderer.measure (007a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  test('defaults are unbounded (infinity) and constrain is a no-op', () {
    const JetConstraints c = JetConstraints();
    expect(c.maxWidth, double.infinity);
    expect(c.maxHeight, double.infinity);
    expect(c.constrain(const JetSize(40, 12)), const JetSize(40, 12));
  });

  test('constrain clamps each axis independently to the max', () {
    const JetConstraints c = JetConstraints(maxWidth: 30, maxHeight: 10);
    expect(c.constrain(const JetSize(40, 8)), const JetSize(30, 8));
    expect(c.constrain(const JetSize(20, 25)), const JetSize(20, 10));
  });

  test('value equality and toString', () {
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7),
        const JetConstraints(maxWidth: 5, maxHeight: 7));
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7),
        isNot(const JetConstraints(maxWidth: 5, maxHeight: 8)));
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7).toString(),
        'JetConstraints(maxWidth: 5.0, maxHeight: 7.0)');
  });
}
