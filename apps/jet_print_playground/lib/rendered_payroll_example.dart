/// Real data for the payroll sample, plus the one-call render through the public
/// engine — the consumer side of the Employee ▸ Earnings / Deductions demo, all
/// through `package:jet_print/jet_print.dart` only.
///
/// Four employees across two departments (Engineering ×2, Sales ×2), ordered by
/// department so the group breaks resolve. Each stub stores its line items AND
/// the authoritative `grossPay` / `totalDeductions` / `netPay`; the live section
/// folds reconcile to gross/deductions and Net is derived on the page. The
/// declared schema (`payrollSchema.fields`) is passed to the data source so the
/// nested `List<Map>` columns are typed as collections and the folds resolve.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'payroll_sample.dart';

/// The sample payroll run — the source of truth the data source and the tests
/// both read, so the rendered totals and the expected sums can never drift.
const List<Map<String, Object?>> kSamplePayroll = <Map<String, Object?>>[
  // --- Engineering ---
  <String, Object?>{
    'empNo': 'E-1001',
    'empName': 'Jane Doe',
    'jobTitle': 'Software Engineer',
    'department': 'Engineering',
    'payPeriod': 'Jun 1–15, 2026',
    'payDate': '2026-06-20',
    'payMethod': 'Direct Deposit ••••1234',
    'verifyToken': 'PAY-E1001-2026-06-B1',
    'grossPay': 3800.00,
    'totalDeductions': 1223.70,
    'netPay': 2576.30,
    'earnings': <Map<String, Object?>>[
      <String, Object?>{'type': 'Regular', 'hours': 80.0, 'rate': 43.75, 'earnAmount': 3500.00, 'earnYtd': 42000.00},
      <String, Object?>{'type': 'Overtime', 'hours': 6.0, 'rate': 50.00, 'earnAmount': 300.00, 'earnYtd': 1800.00},
    ],
    'deductions': <Map<String, Object?>>[
      <String, Object?>{'type': 'Federal Income Tax', 'dedAmount': 560.00, 'dedYtd': 6720.00},
      <String, Object?>{'type': 'Social Security', 'dedAmount': 235.60, 'dedYtd': 2827.20},
      <String, Object?>{'type': 'Medicare', 'dedAmount': 55.10, 'dedYtd': 661.20},
      <String, Object?>{'type': '401(k)', 'dedAmount': 228.00, 'dedYtd': 2736.00},
      <String, Object?>{'type': 'Health Insurance', 'dedAmount': 145.00, 'dedYtd': 1740.00},
    ],
  },
  <String, Object?>{
    'empNo': 'E-1002',
    'empName': 'Carlos Mendez',
    'jobTitle': 'DevOps Engineer',
    'department': 'Engineering',
    'payPeriod': 'Jun 1–15, 2026',
    'payDate': '2026-06-20',
    'payMethod': 'Direct Deposit ••••5678',
    'verifyToken': 'PAY-E1002-2026-06-B1',
    'grossPay': 4340.00,
    'totalDeductions': 1408.41,
    'netPay': 2931.59,
    'earnings': <Map<String, Object?>>[
      <String, Object?>{'type': 'Regular', 'hours': 80.0, 'rate': 48.00, 'earnAmount': 3840.00, 'earnYtd': 46080.00},
      <String, Object?>{'type': 'Bonus', 'hours': 0.0, 'rate': 0.00, 'earnAmount': 500.00, 'earnYtd': 1500.00},
    ],
    'deductions': <Map<String, Object?>>[
      <String, Object?>{'type': 'Federal Income Tax', 'dedAmount': 651.00, 'dedYtd': 7812.00},
      <String, Object?>{'type': 'Social Security', 'dedAmount': 269.08, 'dedYtd': 3228.96},
      <String, Object?>{'type': 'Medicare', 'dedAmount': 62.93, 'dedYtd': 755.16},
      <String, Object?>{'type': '401(k)', 'dedAmount': 260.40, 'dedYtd': 3124.80},
      <String, Object?>{'type': 'Health Insurance', 'dedAmount': 165.00, 'dedYtd': 1980.00},
    ],
  },
  // --- Sales ---
  <String, Object?>{
    'empNo': 'S-2001',
    'empName': 'Aisha Khan',
    'jobTitle': 'Account Executive',
    'department': 'Sales',
    'payPeriod': 'Jun 1–15, 2026',
    'payDate': '2026-06-20',
    'payMethod': 'Direct Deposit ••••9012',
    'verifyToken': 'PAY-S2001-2026-06-B1',
    'grossPay': 4450.00,
    'totalDeductions': 1375.43,
    'netPay': 3074.57,
    'earnings': <Map<String, Object?>>[
      <String, Object?>{'type': 'Regular', 'hours': 80.0, 'rate': 40.00, 'earnAmount': 3200.00, 'earnYtd': 38400.00},
      <String, Object?>{'type': 'Commission', 'hours': 0.0, 'rate': 0.00, 'earnAmount': 1250.00, 'earnYtd': 9800.00},
    ],
    'deductions': <Map<String, Object?>>[
      <String, Object?>{'type': 'Federal Income Tax', 'dedAmount': 667.50, 'dedYtd': 8010.00},
      <String, Object?>{'type': 'Social Security', 'dedAmount': 275.90, 'dedYtd': 3310.80},
      <String, Object?>{'type': 'Medicare', 'dedAmount': 64.53, 'dedYtd': 774.36},
      <String, Object?>{'type': '401(k)', 'dedAmount': 222.50, 'dedYtd': 2670.00},
      <String, Object?>{'type': 'Health Insurance', 'dedAmount': 145.00, 'dedYtd': 1740.00},
    ],
  },
  <String, Object?>{
    'empNo': 'S-2002',
    'empName': 'Tom Becker',
    'jobTitle': 'Sales Associate',
    'department': 'Sales',
    'payPeriod': 'Jun 1–15, 2026',
    'payDate': '2026-06-20',
    'payMethod': 'Direct Deposit ••••3456',
    'verifyToken': 'PAY-S2002-2026-06-B1',
    'grossPay': 3150.00,
    'totalDeductions': 995.98,
    'netPay': 2154.02,
    'earnings': <Map<String, Object?>>[
      <String, Object?>{'type': 'Regular', 'hours': 80.0, 'rate': 31.25, 'earnAmount': 2500.00, 'earnYtd': 30000.00},
      <String, Object?>{'type': 'Commission', 'hours': 0.0, 'rate': 0.00, 'earnAmount': 650.00, 'earnYtd': 5200.00},
    ],
    'deductions': <Map<String, Object?>>[
      <String, Object?>{'type': 'Federal Income Tax', 'dedAmount': 472.50, 'dedYtd': 5670.00},
      <String, Object?>{'type': 'Social Security', 'dedAmount': 195.30, 'dedYtd': 2343.60},
      <String, Object?>{'type': 'Medicare', 'dedAmount': 45.68, 'dedYtd': 548.16},
      <String, Object?>{'type': '401(k)', 'dedAmount': 157.50, 'dedYtd': 1890.00},
      <String, Object?>{'type': 'Health Insurance', 'dedAmount': 125.00, 'dedYtd': 1500.00},
    ],
  },
];

/// The sample payroll run as an in-memory data source, matching [payrollSchema].
/// The declared `fields:` is required so nested `List<Map>` columns are typed as
/// collections (else the section folds render 0).
JetDataSource payrollDataSource() =>
    JetInMemoryDataSource(kSamplePayroll, fields: payrollSchema.fields);

/// Renders [payrollDefinition] over [payrollDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderPayrollDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? payrollDefinition(),
      source ?? payrollDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(payrollSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares, top-level and nested (so
/// collection-scoped bindings like `$F{earnAmount}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
