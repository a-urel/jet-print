/// The design-time binding token (013 T005) mirrors the value-field projection,
/// so the canvas and Properties panel always show the same thing (SC-002).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/binding_token.dart';

void main() {
  test('a simple field reference shows as [name]', () {
    expect(fieldTokenLabel(r'$F{customerName}'), '[customerName]');
  });

  test('a function call shows as {func[field]}', () {
    expect(fieldTokenLabel(r'UPPER($F{name})'), '{upper[name]}');
  });

  test('a CONCAT template shows as {…}', () {
    expect(fieldTokenLabel(r'CONCAT($F{firstName}, " ", $F{lastName})'),
        '{[firstName] [lastName]}');
  });

  test('a legacy/out-of-grammar expression shows verbatim in braces', () {
    expect(fieldTokenLabel(r'$F{a} + $F{b}'), '{\$F{a} + \$F{b}}');
  });
}
