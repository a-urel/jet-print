// FilledReport/FilledBand: value-equal, snapshot-testable IR (007b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 5);
  FilledBand band() => FilledBand(
        type: BandType.detail,
        height: 20,
        elements: const <ReportElement>[TextElement(id: 't', bounds: r, text: 'A')],
        variables: const <String, JetValue>{'total': JetNumber(3)},
      );

  test('FilledBand has value equality including the variables map', () {
    expect(band(), band());
    final FilledBand other = FilledBand(
      type: BandType.detail,
      height: 20,
      elements: const <ReportElement>[TextElement(id: 't', bounds: r, text: 'A')],
      variables: const <String, JetValue>{'total': JetNumber(4)}, // differs
    );
    expect(band(), isNot(other));
  });

  test('FilledReport has value equality over page + bands', () {
    final FilledReport a =
        FilledReport(page: PageFormat.a4Portrait, bands: <FilledBand>[band()]);
    final FilledReport b =
        FilledReport(page: PageFormat.a4Portrait, bands: <FilledBand>[band()]);
    expect(a, b);
    expect(a.bands.single.variables['total'], const JetNumber(3));
  });

  test('FilledBand freezes its nested collections', () {
    final FilledBand b = band();
    expect(() => b.elements.add(b.elements.first), throwsUnsupportedError);
    expect(() => b.variables['x'] = const JetNull(), throwsUnsupportedError);
  });

  test('variables hash is order-independent (matches order-insensitive equality)',
      () {
    final FilledBand a = FilledBand(
      type: BandType.detail,
      height: 20,
      elements: const <ReportElement>[],
      variables: const <String, JetValue>{'a': JetNumber(1), 'b': JetNumber(2)},
    );
    final FilledBand b = FilledBand(
      type: BandType.detail,
      height: 20,
      elements: const <ReportElement>[],
      variables: <String, JetValue>{'b': const JetNumber(2), 'a': const JetNumber(1)},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('variables hash stays order-independent with three distinct entries', () {
    FilledBand make(Map<String, JetValue> vars) => FilledBand(
          type: BandType.detail,
          height: 20,
          elements: const <ReportElement>[],
          variables: vars,
        );
    final FilledBand a = make(const <String, JetValue>{
      'x': JetNumber(1),
      'y': JetNumber(2),
      'z': JetNumber(3),
    });
    final FilledBand b = make(<String, JetValue>{
      'z': const JetNumber(3),
      'x': const JetNumber(1),
      'y': const JetNumber(2),
    });
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('FilledBand.group participates in equality and hashCode', () {
    FilledBand band(String? group) => FilledBand(
          type: BandType.groupHeader,
          height: 10,
          elements: const <ReportElement>[],
          variables: const <String, JetValue>{},
          group: group,
        );
    expect(band('region'), band('region'));
    expect(band('region').hashCode, band('region').hashCode);
    expect(band('region') == band('city'), isFalse);
    expect(band('region') == band(null), isFalse);
  });

  test('FilledBand.group defaults to null and appears in toString when set', () {
    final FilledBand plain = FilledBand(
        type: BandType.detail,
        height: 10,
        elements: const <ReportElement>[],
        variables: const <String, JetValue>{});
    expect(plain.group, isNull);
    final FilledBand grouped = FilledBand(
        type: BandType.groupHeader,
        height: 10,
        elements: const <ReportElement>[],
        variables: const <String, JetValue>{},
        group: 'region');
    expect(grouped.toString(), contains('region'));
  });

  test('FilledReport.params participates in equality and hashCode', () {
    FilledReport report(Map<String, JetValue> params) => FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: params);
    expect(report(<String, JetValue>{'x': const JetString('a')}),
        report(<String, JetValue>{'x': const JetString('a')}));
    expect(report(<String, JetValue>{'x': const JetString('a')}).hashCode,
        report(<String, JetValue>{'x': const JetString('a')}).hashCode);
    expect(
        report(<String, JetValue>{'x': const JetString('a')}) ==
            report(<String, JetValue>{'x': const JetString('b')}),
        isFalse);
  });

  test('FilledReport.params defaults to empty', () {
    final FilledReport r =
        FilledReport(page: PageFormat.a4Portrait, bands: const <FilledBand>[]);
    expect(r.params, isEmpty);
  });

  test('FilledReport.params equality and hash are insertion-order-independent',
      () {
    FilledReport report(Map<String, JetValue> params) => FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: params);
    final FilledReport a = report(<String, JetValue>{
      'a': const JetString('1'),
      'b': const JetString('2'),
    });
    final FilledReport b = report(<String, JetValue>{
      'b': const JetString('2'),
      'a': const JetString('1'),
    });
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('FilledReport freezes its params map', () {
    final FilledReport r = FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: <String, JetValue>{'x': const JetString('a')});
    expect(() => r.params['y'] = const JetString('b'), throwsUnsupportedError);
  });
}
