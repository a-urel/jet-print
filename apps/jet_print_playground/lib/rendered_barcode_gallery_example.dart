/// The consumer side of the barcode-symbology gallery: a single-row data source
/// and the one-call render through the public engine, all via
/// `package:jet_print/jet_print.dart`.
///
/// The gallery is static — every barcode value is a literal in
/// `barcode_gallery_sample.dart` — so the data source carries exactly one
/// (empty) row, which renders the lone detail band once.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'barcode_gallery_sample.dart';

/// A single empty master row: enough to render the detail band once. The cells
/// bind no fields, so the row needs no data.
JetDataSource barcodeGalleryDataSource() =>
    JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]);

/// Renders [barcodeGalleryDefinition] over [barcodeGalleryDataSource] through
/// the native [JetReportEngine.renderDefinition] path — the same single call
/// the designer tab's preview uses. [definition] defaults to the bundled sample
/// so the designer can pass its LIVE edits; [source] defaults to the one-row
/// gallery data.
RenderedReport renderBarcodeGalleryDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? barcodeGalleryDefinition(),
      source ?? barcodeGalleryDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        fonts: fonts,
      ),
    );
