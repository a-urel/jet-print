/// Real data for the nested-list sample, plus the one-call render through the
/// public engine — the consumer side of the Customer ▸ Order ▸ Line demo, all
/// through `package:jet_print/jet_print.dart` only.
///
/// The data mirrors the `customersSchema` shape: customers, each with an
/// `orders` collection, each order with a `lines` collection. Totals roll up
/// consistently (line totals → `orderTotal` → `customerTotal`), so the single
/// engine-computed aggregate — the report `grandTotal` — equals the sum of the
/// displayed customer totals (32.0 + 14.5 + 235.0 = 281.5).
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'nested_list_sample.dart';

/// Three customers with nested orders and line items, matching
/// [customersSchema]. Dates are ISO strings (as in the invoice sample) so the
/// value is source-format agnostic.
JetDataSource customersDataSource() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'customerName': 'Acme GmbH',
        'customerCode': 'C-001',
        'customerTotal': 32.0,
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderNo': 'SO-1042',
            'date': '2026-05-12',
            'orderTotal': 25.5,
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'description': 'Widget',
                'qty': 3,
                'unitPrice': 4.5,
                'lineTotal': 13.5
              },
              <String, Object?>{
                'description': 'Gadget',
                'qty': 1,
                'unitPrice': 12.0,
                'lineTotal': 12.0
              },
            ],
          },
          <String, Object?>{
            'orderNo': 'SO-1051',
            'date': '2026-05-20',
            'orderTotal': 6.5,
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'description': 'Sprocket',
                'qty': 2,
                'unitPrice': 3.25,
                'lineTotal': 6.5
              },
            ],
          },
        ],
      },
      <String, Object?>{
        'customerName': 'Globex SARL',
        'customerCode': 'C-002',
        'customerTotal': 14.5,
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderNo': 'SO-1043',
            'date': '2026-05-14',
            'orderTotal': 14.5,
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'description': 'Bolt',
                'qty': 10,
                'unitPrice': 0.75,
                'lineTotal': 7.5
              },
              <String, Object?>{
                'description': 'Nut',
                'qty': 10,
                'unitPrice': 0.5,
                'lineTotal': 5.0
              },
              <String, Object?>{
                'description': 'Washer',
                'qty': 20,
                'unitPrice': 0.1,
                'lineTotal': 2.0
              },
            ],
          },
        ],
      },
      <String, Object?>{
        'customerName': 'Initech Ltd',
        'customerCode': 'C-003',
        'customerTotal': 235.0,
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderNo': 'SO-1044',
            'date': '2026-05-19',
            'orderTotal': 175.0,
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'description': 'Consulting',
                'qty': 2,
                'unitPrice': 50.0,
                'lineTotal': 100.0
              },
              <String, Object?>{
                'description': 'Onboarding',
                'qty': 1,
                'unitPrice': 75.0,
                'lineTotal': 75.0
              },
            ],
          },
          <String, Object?>{
            'orderNo': 'SO-1060',
            'date': '2026-06-01',
            'orderTotal': 60.0,
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'description': 'Support',
                'qty': 3,
                'unitPrice': 20.0,
                'lineTotal': 60.0
              },
            ],
          },
        ],
      },
    ]);

/// Renders [nestedListsDefinition] over [customersDataSource] through the
/// native [JetReportEngine.renderDefinition] path — the same single call the
/// designer tab's preview uses. [definition] defaults to the bundled sample so
/// the designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderNestedListsDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? nestedListsDefinition(),
      source ?? customersDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(customersSchema.fields),
        fonts: fonts,
      ),
    );

/// The flat set of every field name the schema declares, top-level and nested
/// (so collection-scoped bindings like `$F{lineTotal}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
