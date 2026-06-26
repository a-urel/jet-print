import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('bundled sample invoice.jetreport.datasource decodes', () {
    final String text =
        File('sample_data/invoice.jetreport.datasource').readAsStringSync();
    final JetDataSourceDocument doc = JetDataSourceFile.decodeJson(text);
    expect(doc.schema.name, 'Invoice');
    expect(doc.schema.fields.any((FieldDef f) => f.name == 'lines'), isTrue);
    expect(doc.sample, isNotNull);
  });
}
