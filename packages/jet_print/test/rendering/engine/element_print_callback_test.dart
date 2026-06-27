import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('ElementPrintContext exposes its fields; callback can transform', () {
    const ctx = ElementPrintContext(
      pageNumber: 2,
      pageCount: 5,
      bandType: BandType.detail,
      bandName: 'customer',
      fields: <String, JetValue>{'total': JetNumber(-3)},
      variables: <String, JetValue>{},
    );
    expect(ctx.pageNumber, 2);
    expect(ctx.pageCount, 5);
    expect(ctx.bandType, BandType.detail);
    expect(ctx.bandName, 'customer');
    expect(ctx.fields['total'], const JetNumber(-3));

    final JetElementPrintCallback cb = (el, c) =>
        el is TextElement ? el.copyWith(text: 'p${c.pageNumber}') : el;
    final TextElement src = const TextElement(
      id: 't',
      bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
      text: 'orig',
    );
    final ReportElement? out = cb(src, ctx);
    expect((out! as TextElement).text, 'p2');
  });
}
