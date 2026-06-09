// Lossless round-trip contract for the public `JetReportFormat` facade
// (Phase 2 / T005 / contracts §7.4 / SC-002).
//
// Imports ONLY the public entry point: this test doubles as proof that the
// surfaced format API is sufficient to serialize a full design (FR-003/FR-022).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A fixture exercising all four creatable element types plus the full
/// parameter / variable / group payload carried by a template.
ReportTemplate _fixture() => ReportTemplate(
      name: 'Showcase',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        const ReportBand(
          type: BandType.pageHeader,
          height: 80,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
              text: 'INVOICE',
              style: JetTextStyle(
                fontSize: 20,
                weight: JetFontWeight.bold,
                align: JetTextAlign.center,
              ),
            ),
            ShapeElement(
              id: 'rule',
              bounds: JetRect(x: 0, y: 30, width: 200, height: 0),
              kind: ShapeKind.line,
              style: JetBoxStyle(stroke: JetColor(0xFF000000)),
            ),
            ImageElement(
              id: 'logo',
              bounds: JetRect(x: 220, y: 0, width: 60, height: 30),
              source: UrlImageSource('https://example.com/logo.png'),
            ),
            BarcodeElement(
              id: 'qr',
              bounds: JetRect(x: 220, y: 40, width: 40, height: 40),
              symbology: BarcodeSymbology.qrCode,
              data: 'https://example.com/inv/42',
            ),
          ],
        ),
        const ReportBand(type: BandType.detail, height: 18),
      ],
      parameters: const <ReportParameter>[
        ReportParameter(name: 'asOf', type: JetFieldType.dateTime),
      ],
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'total',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
        ),
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'byCustomer', expression: r'$F{customer}'),
      ],
    );

void main() {
  group('JetReportFormat', () {
    test('stamps the current schema version on encode', () {
      final Map<String, Object?> encoded = JetReportFormat.encode(_fixture());
      expect(encoded['schemaVersion'], isA<int>());
    });

    test('decode(encode(t)) is lossless — re-encode is identical (no reorder)',
        () {
      final ReportTemplate t = _fixture();
      final Map<String, Object?> encoded = JetReportFormat.encode(t);
      final ReportTemplate decoded = JetReportFormat.decode(encoded);
      expect(JetReportFormat.encode(decoded), equals(encoded));
      // Typed elements survive as their concrete types.
      final List<ReportElement> els = decoded.bands.first.elements;
      expect(els[0], isA<TextElement>());
      expect(els[1], isA<ShapeElement>());
      expect(els[2], isA<ImageElement>());
      expect(els[3], isA<BarcodeElement>());
      // The declarations round-trip.
      expect(decoded.parameters.single.name, 'asOf');
      expect(decoded.variables.single.calculation, JetCalculation.sum);
      expect(decoded.groups.single.name, 'byCustomer');
    });

    test('encodeJson / decodeJson round-trip through real JSON text', () {
      final ReportTemplate t = _fixture();
      final String json = JetReportFormat.encodeJson(t);
      expect(() => jsonDecode(json), returnsNormally);
      final ReportTemplate back = JetReportFormat.decodeJson(json);
      expect(JetReportFormat.encode(back), equals(JetReportFormat.encode(t)));
    });

    test('preserves an unknown element type byte-for-byte (Constitution V)',
        () {
      final Map<String, Object?> wire = <String, Object?>{
        'schemaVersion': JetReportFormat.encode(_fixture())['schemaVersion'],
        'name': 'Custom',
        'page': PageFormat.a4Portrait.toJson(),
        'bands': <Object?>[
          <String, Object?>{
            'type': 'detail',
            'height': 20.0,
            'elements': <Object?>[
              <String, Object?>{
                'type': 'customGauge',
                'id': 'g1',
                'bounds': <String, Object?>{
                  'x': 1.0,
                  'y': 2.0,
                  'w': 30.0,
                  'h': 30.0,
                },
                'min': 0,
                'max': 100,
              },
            ],
          },
        ],
      };
      final ReportTemplate decoded =
          JetReportFormat.decodeJson(jsonEncode(wire));
      expect(JetReportFormat.encode(decoded), equals(wire));
    });

    test('throws ReportFormatException on a missing schemaVersion', () {
      expect(
        () => JetReportFormat.decode(<String, Object?>{'name': 'x'}),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('throws ReportFormatException on a version newer than the build', () {
      final int current =
          JetReportFormat.encode(_fixture())['schemaVersion']! as int;
      expect(
        () => JetReportFormat.decode(<String, Object?>{
          'schemaVersion': current + 1,
          'name': 'x',
          'page': PageFormat.a4Portrait.toJson(),
          'bands': <Object?>[],
        }),
        throwsA(isA<ReportFormatException>()),
      );
    });
  });
}
