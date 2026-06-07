import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';

void main() {
  test('ReportFormatException is an Exception that carries its message', () {
    const ReportFormatException exception = ReportFormatException('bad schema');
    expect(exception, isA<Exception>());
    expect(exception.message, 'bad schema');
    expect(exception.toString(), contains('bad schema'));
  });
}
