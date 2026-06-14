import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_definition_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

void main() {
  test('registerBuiltInElementCodecs round-trips all four element types', () {
    final ElementCodecRegistry registry = ElementCodecRegistry();
    registerBuiltInElementCodecs(registry);

    const ReportDefinition definition = ReportDefinition(
      name: 'Showcase',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
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
      body: ReportBody(root: DetailScope(id: 'root')),
    );

    final String wire = jsonEncode(encodeDefinition(definition, registry));
    final ReportDefinition decoded = decodeDefinition(
      (jsonDecode(wire) as Map).cast<String, Object?>(),
      registry,
    );
    expect(encodeDefinition(decoded, registry),
        equals(encodeDefinition(definition, registry)));
    final List<ReportElement> elements = decoded.furniture.pageHeader!.elements;
    expect(elements.length, 4);
    expect(elements[0], isA<TextElement>());
    expect(elements[1], isA<ShapeElement>());
    expect(elements[2], isA<ImageElement>());
    expect(elements[3], isA<BarcodeElement>());
  });
}
