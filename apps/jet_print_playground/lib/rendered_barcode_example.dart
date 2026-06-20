/// Real data for the barcode sample, plus the one-call render through the public
/// engine — the consumer side of the 2-column product-label demo, all through
/// `package:jet_print/jet_print.dart` only.
///
/// [barcodeRecordCount] synthetic products are generated deterministically
/// (cycling a fixed name list; SKUs derived from the index — no RNG, so the
/// output is stable) and fed to the engine as a **flat** list — one product per
/// master row, matching [barcodeSchema]. Each SKU is a genuinely valid EAN-13:
/// a 12-digit base plus a computed mod-10 check digit, so every barcode scans
/// and matches its printed number. The detail band's [ColumnLayout] (see
/// `barcode_sample.dart`) places the labels two-across-then-wrap.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'barcode_sample.dart';

/// How many flat product records the demo ships (two full A4 pages of 14).
const int barcodeRecordCount = 28;

/// Display names cycled across the generated products.
const List<String> _productNames = <String>[
  'Wireless Mouse',
  'USB-C Cable 2m',
  'Mechanical Keyboard',
  'Laptop Stand',
  'Noise-Cancel Headset',
  'Webcam 1080p',
  'Desk Lamp LED',
  'Power Bank 20000mAh',
  'HDMI Adapter',
  'Bluetooth Speaker',
  'Monitor Arm',
  'Ergonomic Chair Pad',
  'Cable Organizer',
  'Phone Dock',
];

/// Retail price for each product in [_productNames] (same index): each product
/// has its own constant price, charm-priced (`.99`) the way a real catalogue
/// reads, so a given product always prints the same price wherever it appears.
const List<double> _productPrices = <double>[
  24.99, // Wireless Mouse
  12.99, // USB-C Cable 2m
  89.99, // Mechanical Keyboard
  39.99, // Laptop Stand
  149.99, // Noise-Cancel Headset
  59.99, // Webcam 1080p
  34.99, // Desk Lamp LED
  45.99, // Power Bank 20000mAh
  9.99, // HDMI Adapter
  79.99, // Bluetooth Speaker
  119.99, // Monitor Arm
  29.99, // Ergonomic Chair Pad
  7.99, // Cable Organizer
  19.99, // Phone Dock
];

/// Computes the EAN-13 check digit for a 12-digit [base] and returns the full
/// 13-digit code. The check digit weights digits 3-1 alternating **from the
/// right** of the 12-digit base, so it survives the standard scanner check —
/// the same mod-10 rule the engine's barcode auto-fix uses.
String _ean13(String base) {
  assert(base.length == 12, 'EAN-13 base must be 12 digits');
  int sum = 0;
  for (int i = 0; i < 12; i++) {
    final int digit = base.codeUnitAt(i) - 0x30;
    // Rightmost base digit (i == 11) carries weight 3, then alternate.
    sum += digit * (i.isEven ? 1 : 3);
  }
  final int check = (10 - (sum % 10)) % 10;
  return '$base$check';
}

/// [barcodeRecordCount] flat product maps (`product`/`price`/`sku`), generated
/// deterministically so the sample is reproducible: the name cycles the fixed
/// list, the price is a stable function of the row index, and the SKU is a
/// unique, valid EAN-13 derived from the row index.
List<Map<String, Object?>> _products() => <Map<String, Object?>>[
      for (int i = 0; i < barcodeRecordCount; i++)
        <String, Object?>{
          'product': _productNames[i % _productNames.length],
          // Each product's own constant price (parallel list, same index).
          'price': _productPrices[i % _productPrices.length],
          // 12-digit base (well within int range), then + check digit.
          'sku': _ean13((400000000000 + i * 137).toString().padLeft(12, '0')),
        },
    ];

/// The flat product rows as an in-memory data source, matching [barcodeSchema] —
/// one product per master row. The detail band's [ColumnLayout] turns them into
/// a 2-across-then-wrap sheet; no pre-chunking.
JetDataSource barcodeDataSource() => JetInMemoryDataSource(_products());

/// Renders [barcodeSampleDefinition] over [barcodeDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderBarcodeDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? barcodeSampleDefinition(),
      source ?? barcodeDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: <String>{
          for (final FieldDef f in barcodeSchema.fields) f.name,
        },
        fonts: fonts,
      ),
    );
