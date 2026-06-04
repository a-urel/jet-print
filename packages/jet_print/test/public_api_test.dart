// Public-API import test (US1 / SC-001 / SC-007).
//
// Acts as an external consumer: it imports ONLY the single public entry point
// and proves the documented surface (JetPrintPlaceholder + jetPrintVersion) is
// reachable and sufficient. If this file ever needs a `package:jet_print/src/`
// import to do its job, the public API is incomplete.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('jetPrintVersion is exposed as a non-empty String', () {
    expect(jetPrintVersion, isA<String>());
    expect(jetPrintVersion, isNotEmpty);
  });

  test('JetPrintPlaceholder is const-constructible and is a Widget', () {
    const placeholder = JetPrintPlaceholder();
    expect(placeholder, isA<Widget>());
  });
}
