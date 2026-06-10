// test/rendering/export/support/export_fixtures.dart
/// Shared rendered-report fixtures for the export tests (012). Everything is
/// deterministic: in-memory data, embedded image bytes generated with
/// `package:image`, and the same invoice shape the preview goldens pin.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';

/// US Letter: 612 x 792 pt.
const PageFormat letterPage =
    PageFormat(width: 612, height: 792, margins: JetEdgeInsets.all(36));

/// An odd custom sheet, to prove FR-008 is not format-table lookup.
const PageFormat customPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(8));

/// The two-page invoice the preview goldens pin (rendered_invoice_test.dart):
/// master fields, 12 iterated line items, bold total, page-footer page numbers.
ReportTemplate invoiceTemplate() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat(width: 400, height: 300, margins: JetEdgeInsets.all(16)),
      bands: <ReportBand>[
        ReportBand(
          type: BandType.title,
          height: 28,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 160, height: 24),
              text: 'INVOICE',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
          ],
        ),
        ReportBand(
          type: BandType.detail,
          height: 36,
          elements: <ReportElement>[
            TextElement(
              id: 'invoiceNo',
              bounds: JetRect(x: 220, y: 2, width: 148, height: 14),
              text: 'invoiceNo',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{invoiceNo}',
            ),
            TextElement(
              id: 'customer',
              bounds: JetRect(x: 0, y: 2, width: 220, height: 14),
              text: 'customer',
              expression: r'$F{customerName}',
            ),
          ],
        ),
        ReportBand(
          type: BandType.detail,
          height: 18,
          collectionField: 'lines',
          elements: <ReportElement>[
            TextElement(
              id: 'desc',
              bounds: JetRect(x: 0, y: 1, width: 180, height: 14),
              text: 'desc',
              expression: r'$F{description}',
            ),
            TextElement(
              id: 'qty',
              bounds: JetRect(x: 190, y: 1, width: 40, height: 14),
              text: 'qty',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{qty}',
            ),
            TextElement(
              id: 'lineTotal',
              bounds: JetRect(x: 240, y: 1, width: 128, height: 14),
              text: 'lineTotal',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'FORMAT($F{qty} * $F{unitPrice}, "#,##0.00")',
            ),
          ],
        ),
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'totalLabel',
              bounds: JetRect(x: 190, y: 8, width: 40, height: 14),
              text: 'Total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'total',
              bounds: JetRect(x: 240, y: 8, width: 128, height: 14),
              text: 'total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'FORMAT($F{total}, "#,##0.00")',
            ),
          ],
        ),
        ReportBand(
          type: BandType.pageFooter,
          height: 16,
          elements: <ReportElement>[
            TextElement(
              id: 'pf',
              bounds: JetRect(x: 0, y: 1, width: 368, height: 12),
              text: '',
              style: JetTextStyle(fontSize: 9, align: JetTextAlign.center),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ],
    );

/// The invoice's deterministic in-memory dataset (12 lines -> 2 pages).
JetInMemoryDataSource invoiceSource() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'invoiceNo': 'INV-1042',
        'customerName': 'Acme GmbH',
        'total': 318.0,
        'lines': <Map<String, Object?>>[
          for (int i = 1; i <= 12; i++)
            <String, Object?>{
              'description': 'Line item $i',
              'qty': i,
              'unitPrice': 4.0,
            },
        ],
      },
    ]);

/// Renders the invoice fixture (the export-side twin of the preview goldens).
RenderedReport invoiceReport() =>
    const JetReportEngine().render(invoiceTemplate(), invoiceSource());

/// A one-element static report on [page] saying [text].
RenderedReport textOnlyReport(PageFormat page, {String text = 'Hello export'}) {
  final ReportTemplate template = ReportTemplate(
    name: 'text-only',
    page: page,
    bands: <ReportBand>[
      ReportBand(
        type: BandType.title,
        height: 20,
        elements: <ReportElement>[
          TextElement(
            id: 't',
            bounds: const JetRect(x: 0, y: 0, width: 150, height: 16),
            text: text,
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine()
      .render(template, JetInMemoryDataSource(const <Map<String, Object?>>[]));
}

/// A deterministic 4x2 PNG with full alpha (RGBA path in the PDF embedder).
Uint8List tinyPngBytes() => img.encodePng(_tinyImage());

/// The same pixels as a baseline JPEG (the passthrough path).
Uint8List tinyJpegBytes() => img.encodeJpg(_tinyImage(), quality: 90);

img.Image _tinyImage() {
  final img.Image im = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      im.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return im;
}

/// A report with one embedded image of known 4x2 pixels under [fit].
RenderedReport imageReport({
  required Uint8List bytes,
  JetBoxFit fit = JetBoxFit.contain,
}) {
  final ReportTemplate template = ReportTemplate(
    name: 'image',
    page: customPage,
    bands: <ReportBand>[
      ReportBand(
        type: BandType.title,
        height: 70,
        elements: <ReportElement>[
          ImageElement(
            id: 'img',
            bounds: const JetRect(x: 10, y: 10, width: 60, height: 40),
            source: BytesImageSource(bytes),
            fit: fit,
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine()
      .render(template, JetInMemoryDataSource(const <Map<String, Object?>>[]));
}

/// An empty dataset over a template with static chrome: the preview shows the
/// static pages, so the artifact must too (never zero-page) — SC-007.
RenderedReport emptyDatasetReport() {
  final ReportTemplate template = ReportTemplate(
    name: 'empty',
    page: customPage,
    bands: const <ReportBand>[
      ReportBand(
        type: BandType.title,
        height: 20,
        elements: <ReportElement>[
          TextElement(
            id: 'title',
            bounds: JetRect(x: 0, y: 0, width: 150, height: 16),
            text: 'Static title',
          ),
        ],
      ),
      ReportBand(
        type: BandType.detail,
        height: 16,
        elements: <ReportElement>[
          TextElement(
            id: 'row',
            bounds: JetRect(x: 0, y: 0, width: 150, height: 14),
            text: 'row',
            expression: r'$F{name}',
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine()
      .render(template, JetInMemoryDataSource(const <Map<String, Object?>>[]));
}

/// A URL image source with no resolver: the layouter substitutes the shared
/// placeholder primitives (outline rect + label), and records a diagnostic.
RenderedReport unresolvedImageReport() {
  final ReportTemplate template = ReportTemplate(
    name: 'unresolved-image',
    page: customPage,
    bands: const <ReportBand>[
      ReportBand(
        type: BandType.title,
        height: 60,
        elements: <ReportElement>[
          ImageElement(
            id: 'remote',
            bounds: JetRect(x: 10, y: 5, width: 80, height: 40),
            source: UrlImageSource('https://example.com/logo.png'),
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine()
      .render(template, JetInMemoryDataSource(const <Map<String, Object?>>[]));
}

/// One good binding plus one failing expression (unknown field): the bad
/// element falls back blank with a diagnostic; the good one renders.
RenderedReport failedExpressionReport() {
  final ReportTemplate template = ReportTemplate(
    name: 'failed-expression',
    page: customPage,
    bands: const <ReportBand>[
      ReportBand(
        type: BandType.detail,
        height: 40,
        elements: <ReportElement>[
          TextElement(
            id: 'good',
            bounds: JetRect(x: 0, y: 0, width: 150, height: 14),
            text: 'good',
            expression: r'$F{name}',
          ),
          TextElement(
            id: 'bad',
            bounds: JetRect(x: 0, y: 18, width: 150, height: 14),
            text: 'bad',
            expression: r'$F{nope}',
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine().render(
    template,
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'name': 'alpha'},
    ]),
  );
}

/// The 011 1,000-record performance dataset shape (SC-005).
RenderedReport performanceReport({int records = 1000}) {
  const ReportTemplate template = ReportTemplate(
    name: 'big',
    page: PageFormat.a4Portrait,
    bands: <ReportBand>[
      ReportBand(
        type: BandType.detail,
        height: 20,
        elements: <ReportElement>[
          TextElement(
            id: 'name',
            bounds: JetRect(x: 0, y: 0, width: 240, height: 16),
            text: 'name',
            expression: r'$F{name}',
          ),
          TextElement(
            id: 'amount',
            bounds: JetRect(x: 260, y: 0, width: 120, height: 16),
            text: 'amount',
            expression: r'$F{amount}',
          ),
        ],
      ),
    ],
  );
  return const JetReportEngine().render(
    template,
    JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < records; i++)
        <String, Object?>{'name': 'record $i', 'amount': i * 1.5},
    ]),
  );
}
