// Lossless round-trip contract for the public `JetReportFormat` facade
// (Phase 2 / T005 / contracts §7.4 / SC-002).
//
// Imports ONLY the public entry point: this test doubles as proof that the
// surfaced format API is sufficient to serialize a full design (FR-003/FR-022).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A fixture exercising all four creatable element types plus the full
/// parameter / variable / group payload carried by a definition.
ReportDefinition _fixture() => ReportDefinition(
      name: 'Showcase',
      page: PageFormat.a4Portrait,
      furniture: const PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
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
      ),
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
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'byCustomer', key: r'$F{customer}'),
          ],
          children: <ScopeNode>[
            BandNode(
              Band(id: 'detail', type: BandType.detail, height: 18),
            ),
          ],
        ),
      ),
    );

void main() {
  group('JetReportFormat', () {
    test('stamps the current schema version on encode', () {
      final Map<String, Object?> encoded =
          JetReportFormat.encodeDefinition(_fixture());
      expect(encoded['schemaVersion'], isA<int>());
    });

    test('decode(encode(d)) is lossless — re-encode is identical (no reorder)',
        () {
      final ReportDefinition d = _fixture();
      final Map<String, Object?> encoded = JetReportFormat.encodeDefinition(d);
      final ReportDefinition decoded =
          JetReportFormat.decodeDefinition(encoded);
      expect(JetReportFormat.encodeDefinition(decoded), equals(encoded));
      // Typed elements survive as their concrete types.
      final List<ReportElement> els = decoded.furniture.pageHeader!.elements;
      expect(els[0], isA<TextElement>());
      expect(els[1], isA<ShapeElement>());
      expect(els[2], isA<ImageElement>());
      expect(els[3], isA<BarcodeElement>());
      // The declarations round-trip.
      expect(decoded.parameters.single.name, 'asOf');
      expect(decoded.variables.single.calculation, JetCalculation.sum);
      expect(decoded.body.root.groups.single.name, 'byCustomer');
    });

    test('encodeJson / decodeJson round-trip through real JSON text', () {
      final ReportDefinition d = _fixture();
      final String json = JetReportFormat.encodeDefinitionJson(d);
      expect(() => jsonDecode(json), returnsNormally);
      final ReportDefinition back = JetReportFormat.decodeDefinitionJson(json);
      expect(JetReportFormat.encodeDefinition(back),
          equals(JetReportFormat.encodeDefinition(d)));
    });

    test('preserves an unknown element type byte-for-byte (Constitution V)',
        () {
      final Map<String, Object?> wire = <String, Object?>{
        'schemaVersion':
            JetReportFormat.encodeDefinition(_fixture())['schemaVersion'],
        'name': 'Custom',
        'page': PageFormat.a4Portrait.toJson(),
        'furniture': <String, Object?>{},
        'body': <String, Object?>{
          'root': <String, Object?>{
            'id': 'root',
            'children': <Object?>[
              <String, Object?>{
                'kind': 'band',
                'band': <String, Object?>{
                  'id': 'detail',
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
              },
            ],
          },
        },
      };
      final ReportDefinition decoded =
          JetReportFormat.decodeDefinitionJson(jsonEncode(wire));
      expect(JetReportFormat.encodeDefinition(decoded), equals(wire));
    });

    test('throws ReportFormatException on a missing schemaVersion', () {
      expect(
        () => JetReportFormat.decodeDefinition(<String, Object?>{'name': 'x'}),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('throws ReportFormatException on a version newer than the build', () {
      final int current =
          JetReportFormat.encodeDefinition(_fixture())['schemaVersion']! as int;
      expect(
        () => JetReportFormat.decodeDefinition(<String, Object?>{
          'schemaVersion': current + 1,
          'name': 'x',
          'page': PageFormat.a4Portrait.toJson(),
          'furniture': <String, Object?>{},
          'body': <String, Object?>{
            'root': <String, Object?>{'id': 'root'},
          },
        }),
        throwsA(isA<ReportFormatException>()),
      );
    });
  });
}
