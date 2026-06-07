// VariableRefExpr canonical toString (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/ast.dart';

void main() {
  test('renders a variable reference canonically', () {
    expect(VariableRefExpr('total').toString(), '(var total)');
  });
}
