// Unavailable host family — codec & export portability (022 — C11 / US2; T023).
//
// A report naming a host family NOT registered in the current session stays
// fully portable: it round-trips byte-identically through the codecs (name
// preserved, schemaVersion unchanged — no schema change, Principle V), renders
// via the fallback font, and exports without blocking on the missing font.
// This is the existing 021 unavailable-family path, now exercised for a
// host-contributed name (data-model §8 — no new code). White-box.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import 'export/support/pdf_inspector.dart';

const String _ghost = 'Ghost Brand'; // never registered this session

ReportDefinition _definition() => const ReportDefinition(
      name: 'Portable',
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
                  bounds: JetRect(x: 0, y: 0, width: 240, height: 20),
                  text: 'Portable text',
                  style: JetTextStyle(fontFamily: _ghost),
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
  test('a report naming an unregistered family round-trips byte-identically',
      () {
    final String json = JetReportFormat.encodeDefinitionJson(_definition());
    expect(json, contains(_ghost), reason: 'the stored name is preserved');
    final ReportDefinition reopened =
        JetReportFormat.decodeDefinitionJson(json);
    expect(JetReportFormat.encodeDefinitionJson(reopened), json,
        reason: 'no silent rewrite — byte-identical round-trip (SC-003)');
    // No schema change within the reified format (Principle V).
    expect(JetReportFormat.encodeDefinition(_definition())['schemaVersion'], 2);
    expect(json, contains('"schemaVersion":2'));
  });

  test('the engine renders the unregistered family via the fallback', () {
    // Empty fonts → "Ghost Brand" is unregistered; rendering must not throw and
    // the carried registry resolves it to the default bytes (fallback).
    final RenderedReport report =
        const JetReportEngine().renderDefinition(_definition(), _source());
    expect(report.pageCount, greaterThan(0));
    // The carried registry falls back to default for the unknown family.
    expect(report.fonts.bytesFor(_ghost), isA<Uint8List>());
    expect(report.fonts.resolveFamily(_ghost), isNot(_ghost),
        reason: 'an unregistered family resolves to the default for paint');
  });

  test('export succeeds on the fallback without blocking on the missing font',
      () async {
    final RenderedReport report =
        const JetReportEngine().renderDefinition(_definition(), _source());
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    expect(PdfInspector(pdf).allText, contains('Portable text'),
        reason: 'text still renders (in the fallback) and stays selectable');
    final Uint8List png = await const JetReportExporter().pageToPng(report, 0);
    expect(png, isNotEmpty);
  });
}
