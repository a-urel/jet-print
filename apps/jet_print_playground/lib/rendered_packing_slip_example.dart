/// Real data for the packing-slip sample, plus the one-call render through the
/// public engine — the consumer side of the Shipment ▸ Box ▸ Item demo, all
/// through `package:jet_print/jet_print.dart` only.
///
/// One deterministic shipment of three boxes (2 / 3 / 2 items). The only stored
/// measures are each item's `qtyShipped` and `lineWeight`; every subtotal/total
/// is computed live (per-box footer folds its items; the shipment footer
/// descends [boxes, items] and counts [boxes]). The declared schema
/// (`shipmentSchema.fields`) is passed to the data source so nested `List<Map>`
/// columns are typed as collections and descend paths resolve correctly.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'packing_slip_sample.dart';

/// The single sample shipment — the source of truth the data source and tests
/// both read, so the rendered totals and the expected sums can never drift.
const List<Map<String, Object?>> kSampleShipment = <Map<String, Object?>>[
  <String, Object?>{
    'shipmentNo': 'SH-20488',
    'shipDate': '2026-06-19',
    'orderNo': 'SO-1042',
    'carrier': 'UPS Standard',
    'trackingNo': '1Z999AA10123456784',
    'shipToName': 'Globex SARL',
    'shipToAddress': 'Attn: Receiving Dock\n12 Rue de l’Industrie\n69007 Lyon\nFrance',
    'billToName': 'Globex SARL — Accounts Payable',
    'billToAddress': 'BP 4471\n69356 Lyon CEDEX 07\nFrance',
    'boxes': <Map<String, Object?>>[
      <String, Object?>{
        'boxNo': 'B-01',
        'dimensions': '40 × 30 × 25 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-1001',
            'description': 'Wireless Mouse',
            'attributes': 'Color: Black',
            'lotNo': 'LOT-A1',
            'qtyShipped': 4,
            'lineWeight': 0.480,
          },
          <String, Object?>{
            'sku': 'SKU-1002',
            'description': 'USB-C Cable 2m',
            'attributes': 'Length: 2m',
            'lotNo': 'LOT-A2',
            'qtyShipped': 10,
            'lineWeight': 0.350,
          },
        ],
      },
      <String, Object?>{
        'boxNo': 'B-02',
        'dimensions': '60 × 40 × 30 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-2001',
            'description': 'Mechanical Keyboard',
            'attributes': 'Layout: US',
            'lotNo': 'LOT-B1',
            'qtyShipped': 2,
            'lineWeight': 2.400,
          },
          <String, Object?>{
            'sku': 'SKU-2002',
            'description': 'Laptop Stand',
            'attributes': 'Color: Silver',
            'lotNo': 'LOT-B2',
            'qtyShipped': 3,
            'lineWeight': 1.200,
          },
          <String, Object?>{
            'sku': 'SKU-2003',
            'description': 'Webcam 1080p',
            'attributes': 'FOV: 90°',
            'lotNo': 'LOT-B3',
            'qtyShipped': 5,
            'lineWeight': 0.250,
          },
        ],
      },
      <String, Object?>{
        'boxNo': 'B-03',
        'dimensions': '30 × 20 × 15 cm',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'sku': 'SKU-3001',
            'description': 'Desk Lamp LED',
            'attributes': 'Color: White',
            'lotNo': 'LOT-C1',
            'qtyShipped': 1,
            'lineWeight': 0.900,
          },
          <String, Object?>{
            'sku': 'SKU-3002',
            'description': 'HDMI Adapter',
            'attributes': 'Type: 4K',
            'lotNo': 'LOT-C2',
            'qtyShipped': 8,
            'lineWeight': 0.060,
          },
        ],
      },
    ],
  },
];

/// The single sample shipment as an in-memory data source, matching
/// [shipmentSchema]. The declared `fields:` is required so nested `List<Map>`
/// columns are typed as collections (else descend-path aggregates render 0).
JetDataSource packingSlipDataSource() =>
    JetInMemoryDataSource(kSampleShipment, fields: shipmentSchema.fields);

/// Renders [packingSlipDefinition] over [packingSlipDataSource] through the
/// native [JetReportEngine.renderDefinition] path — the same single call the
/// designer tab's preview uses. [definition] defaults to the bundled sample so
/// the designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderPackingSlipDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? packingSlipDefinition(),
      source ?? packingSlipDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(shipmentSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares, top-level and nested (so
/// collection-scoped bindings like `$F{qtyShipped}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
