// Engine builds + carries one font registry (022 — contract C7; T007).
//
// `JetReportEngine.render` builds a single `FontRegistry`
// (registerDefault + registerHostFonts) and ATTACHES it to the returned
// `RenderedReport`, so preview/export/print read the very bytes layout was
// measured with — WYSIWYG by construction (Principle IV). White-box: reaches
// the internal `RenderedReport.fonts`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';

import '../../support/test_fonts.dart';

ReportDefinition _template() => const ReportDefinition(
      name: 'Carry',
      page: PageFormat(width: 300, height: 200, margins: JetEdgeInsets.all(10)),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 40,
              elements: <ReportElement>[
                TextElement(
                  id: 't',
                  bounds: JetRect(x: 0, y: 0, width: 200, height: 20),
                  text: 'Hello',
                  style: JetTextStyle(fontFamily: 'Acme Brand'),
                ),
              ],
            )),
          ],
        ),
      ),
    );

JetDataSource _source() =>
    JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]);

void main() {
  test('a host-font render carries a registry that resolves the host family',
      () {
    final Uint8List bytes = validRegularFontBytes();
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _template(),
      _source(),
      options: RenderOptions(
        fonts: <JetFontFamily>[
          JetFontFamily(
              name: 'Acme Brand',
              faces: <JetFontFace>[JetFontFace(bytes: bytes)]),
        ],
      ),
    );
    expect(report.fonts, isA<FontRegistry>());
    expect(report.fonts.bytesFor('Acme Brand'), same(bytes),
        reason: 'the carried registry resolves the host face bytes');
    expect(report.fonts.families, contains('Acme Brand'));
  });

  test('an empty-fonts render carries a default-only registry', () {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _template(),
      _source(),
    );
    expect(report.fonts.hasDefault, isTrue);
    // Default-only: the unregistered "Acme Brand" falls back to the default.
    expect(report.fonts.bytesFor('Acme Brand'),
        same(report.fonts.bytesFor(FontRegistry.defaultFamily)));
    expect(report.fonts.families, <String>[FontRegistry.defaultFamily]);
  });
}
