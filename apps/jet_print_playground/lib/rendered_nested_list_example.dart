/// Real data for the nested-list sample, plus the one-call render through the
/// public engine — the consumer side of the Customer ▸ Order ▸ Line demo, all
/// through `package:jet_print/jet_print.dart` only.
///
/// The data mirrors the `customersSchema` shape: customers, each with an
/// `orders` collection, each order with a `lines` collection. The only stored
/// money figure is each line's `lineTotal`; every total above it is computed
/// live via inline multi-level aggregates (spec 033) — each footer authors
/// `SUM($F{lineTotal})` and the engine descends the [orders, lines] path at
/// fill time. The declared schema (`customersSchema.fields`) is passed to the
/// data source so nested `List<Map>` columns are typed as collections and
/// descend paths resolve correctly at the root scope
/// (13.5+12.0+6.5 + 7.5+5.0+2.0 + 100.0+75.0+60.0 = 281.5).
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'nested_list_sample.dart';

/// The sample customers/orders/lines rows — the single source of truth shared
/// by the data source and tests.
///
/// Three customers with nested orders and line items, matching
/// [customersSchema]. Dates are ISO strings (as in the invoice sample) so the
/// value is source-format agnostic. Tests derive their expected per-order
/// line-sums from these exact numbers, so the proof and the render can never
/// silently drift apart.
const List<Map<String, Object?>> kSampleCustomers = <Map<String, Object?>>[
  <String, Object?>{
    'customerName': 'Acme GmbH',
    'customerCode': 'C-001',
    'orders': <Map<String, Object?>>[
      <String, Object?>{
        'orderNo': 'SO-1042',
        'date': '2026-05-12',
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
    'orders': <Map<String, Object?>>[
      <String, Object?>{
        'orderNo': 'SO-1043',
        'date': '2026-05-14',
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
    'orders': <Map<String, Object?>>[
      <String, Object?>{
        'orderNo': 'SO-1044',
        'date': '2026-05-19',
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
];

/// Three customers with nested orders and line items, matching
/// [customersSchema], built from the shared [kSampleCustomers] rows — the
/// single source of truth the tests also derive their expected sums from.
///
/// The declared schema (`fields: customersSchema.fields`) is required: source-
/// level inference does NOT type nested `List<Map>` columns as collections, so
/// without it the root-scope descend paths for inline multi-level aggregates
/// (spec 033) would silently render 0.
JetDataSource customersDataSource() =>
    JetInMemoryDataSource(kSampleCustomers, fields: customersSchema.fields);

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
