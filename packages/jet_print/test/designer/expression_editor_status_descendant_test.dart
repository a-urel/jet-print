library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/panels/expression_editor_dialog.dart';

void main() {
  const Set<String> names = <String>{'customerCode'}; // in-scope at this band
  const Set<String> deep = <String>{'lineTotal'}; // descendant operand

  test('a descendant leaf as an aggregate operand is Valid', () {
    expect(statusFor('{SUM([lineTotal])}', names, descendantOperands: deep),
        isA<StatusValid>());
  });

  test('a bare descendant leaf is Unresolved', () {
    final EditorStatus s =
        statusFor('[lineTotal]', names, descendantOperands: deep);
    expect(s, isA<StatusUnresolved>());
    expect((s as StatusUnresolved).name, 'lineTotal');
  });

  test('an in-scope field stays Valid', () {
    expect(statusFor('[customerCode]', names, descendantOperands: deep),
        isA<StatusValid>());
  });

  test('an unknown operand is Unresolved', () {
    final EditorStatus s =
        statusFor('{SUM([nope])}', names, descendantOperands: deep);
    expect(s, isA<StatusUnresolved>());
    expect((s as StatusUnresolved).name, 'nope');
  });

  test('a compound aggregate with a descendant operand is Valid', () {
    expect(
        statusFor('{SUM([lineTotal]) * 1.1}', names, descendantOperands: deep),
        isA<StatusValid>());
  });
}
