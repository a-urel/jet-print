# Payroll Sample (Playground) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a comprehensive, real-world "Payroll" report sample (department-grouped multi-employee pay stubs) to the `jet_print_playground` app, between the Packing slip and List tabs, using the library's public API only.

**Architecture:** Mirror the existing paired-file sample convention. `payroll_sample.dart` holds the `JetDataSchema` and the `ReportDefinition` (band tree). `rendered_payroll_example.dart` holds the deterministic sample data, the in-memory data source, and the one-call render entry point. The tab is registered in `main.dart`; the label is localized via the three `.arb` files. Employees are master rows grouped by an outer `department` `GroupLevel` and an inner `employee` `GroupLevel`; earnings and deductions are two parallel `NestedScope`s under the employee. No engine changes.

**Tech Stack:** Dart / Flutter, `package:jet_print/jet_print.dart` (public API), `shadcn_ui` (tab UI), `intl` (number formatting in tests), Flutter `gen-l10n`.

## Global Constraints

- **Public API only:** import `package:jet_print/jet_print.dart`. No `package:jet_print/src/...` imports in the two sample library files. (Tests MAY reach into `src/` for render primitives, exactly as `rendered_packing_slip_example_test.dart` does.)
- **No engine changes:** do not modify anything under `packages/jet_print/lib/`.
- **Each `DetailScope` has ≤1 per-row `BandNode`** (the engine renders only one; 2+ trigger an info diagnostic). Section headings live in group-header / scope-footer slots, never as extra sibling bands.
- **Aggregate sinks only:** `SUM(...)` may appear only in the `summary` band, a root group footer, or a nested-scope footer. Net pay uses field arithmetic `$F{grossPay} - $F{totalDeductions}`, NOT `SUM(a) - SUM(b)`.
- **`validate(payrollDefinition())` MUST be empty** (pristine, like the packing slip).
- **Currency:** USD, `en` locale, number format `#,##0.00` (no currency glyph in the pattern — the "USD" note lives in plain label text, matching the packing-slip approach).
- **Sample data ordered by `department`** so group breaks resolve correctly.
- **Content width:** A4 portrait, usable width ≈ 538 pt (reuse the packing slip's x-extent).
- **Run all commands from** `apps/jet_print_playground/` unless stated otherwise.

---

### Task 1: Schema + report definition (`payroll_sample.dart`)

**Files:**
- Create: `apps/jet_print_playground/lib/payroll_sample.dart`
- Test: `apps/jet_print_playground/test/payroll_definition_test.dart`

**Interfaces:**
- Produces:
  - `const JetDataSchema payrollSchema` — `Employee` master fields + `earnings[]` + `deductions[]` collections.
  - `ReportDefinition payrollDefinition()` — the full band tree.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/payroll_definition_test.dart`:

```dart
// Confirms the payroll sample (Employee ▸ earnings / deductions) is authored as
// a department-grouped, dual-nested tree in the reified band model: two parallel
// nested collections under the employee, master-scope subtotals/grand totals as
// inline aggregates, a verification QR — pristine under the validator. All
// through `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/payroll_sample.dart';

void main() {
  group('payroll sample', () {
    test('schema is Employee ▸ earnings / deductions with stored measures', () {
      final FieldDef earnings =
          payrollSchema.fields.firstWhere((FieldDef f) => f.name == 'earnings');
      final FieldDef deductions = payrollSchema.fields
          .firstWhere((FieldDef f) => f.name == 'deductions');
      expect(earnings.type, JetFieldType.collection);
      expect(deductions.type, JetFieldType.collection);
      expect(
        earnings.fields.firstWhere((FieldDef f) => f.name == 'earnAmount').type,
        JetFieldType.double,
      );
      expect(
        deductions.fields.firstWhere((FieldDef f) => f.name == 'dedAmount').type,
        JetFieldType.double,
      );
      // Authoritative employee-level totals are stored, too.
      for (final String name in <String>['grossPay', 'totalDeductions', 'netPay']) {
        expect(payrollSchema.fields.firstWhere((FieldDef f) => f.name == name).type,
            JetFieldType.double);
      }
    });

    test('is grouped department ▸ employee with two parallel nested scopes', () {
      final ReportDefinition def = payrollDefinition();
      final DetailScope root = def.body.root;

      // Master scope iterates employees (no collectionField on root).
      expect(root.collectionField, isNull);

      // Two group levels, outermost first: department then employee.
      expect(root.groups, hasLength(2));
      expect(root.groups[0].key, r'$F{department}');
      expect(root.groups[1].key, r'$F{empNo}');
      expect(root.groups[0].header?.type, BandType.groupHeader);
      expect(root.groups[0].footer?.type, BandType.groupFooter);
      expect(root.groups[1].header?.type, BandType.groupHeader);
      expect(root.groups[1].footer?.type, BandType.groupFooter);

      // Employee scope holds exactly two NestedScopes (no per-row bands) —
      // earnings and deductions in order.
      expect(root.children.whereType<BandNode>(), isEmpty);
      final List<DetailScope> nested = root.children
          .whereType<NestedScope>()
          .map((NestedScope n) => n.scope)
          .toList();
      expect(nested.map((DetailScope s) => s.collectionField),
          <String>['earnings', 'deductions']);
      // Each nested scope has exactly one per-row band and a footer.
      for (final DetailScope s in nested) {
        expect(s.children.whereType<BandNode>(), hasLength(1));
        expect((s.children.single as BandNode).band.type, BandType.detail);
        expect(s.footer?.type, BandType.groupFooter);
      }
    });

    test('totals are inline aggregates in legal sinks; net is arithmetic', () {
      final ReportDefinition def = payrollDefinition();
      expect(def.variables, isEmpty);
      final DetailScope root = def.body.root;
      final DetailScope earnings = root.children
          .whereType<NestedScope>()
          .firstWhere((NestedScope n) => n.scope.collectionField == 'earnings')
          .scope;
      final DetailScope deductions = root.children
          .whereType<NestedScope>()
          .firstWhere((NestedScope n) => n.scope.collectionField == 'deductions')
          .scope;

      TextElement el(Band b, String id) =>
          b.elements.firstWhere((ReportElement e) => e.id == id) as TextElement;

      // Section folds (same-scope, spec 029).
      expect(el(earnings.footer!, 'grossValue').expression, r'SUM($F{earnAmount})');
      expect(el(deductions.footer!, 'totalDedValue').expression,
          r'SUM($F{dedAmount})');

      // Net pay = field arithmetic in the employee group footer.
      expect(el(root.groups[1].footer!, 'netValue').expression,
          r'$F{grossPay} - $F{totalDeductions}');

      // Department subtotals (master-scope, spec 028) and grand totals (summary).
      expect(el(root.groups[0].footer!, 'deptNet').expression, r'SUM($F{netPay})');
      expect(el(def.body.summary!, 'grandGross').expression, r'SUM($F{grossPay})');
      expect(el(def.body.summary!, 'grandNet').expression, r'SUM($F{netPay})');
    });

    test('the verification code is a QR bound to verifyToken', () {
      final ReportDefinition def = payrollDefinition();
      final BarcodeElement qr = def.body.root.groups[1].header!.elements
          .firstWhere((ReportElement e) => e.id == 'verifyQr') as BarcodeElement;
      expect(qr.symbology, BarcodeSymbology.qrCode);
      expect(qr.dataField, 'verifyToken');
      expect(qr.data, isNotEmpty);
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(payrollDefinition()), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/payroll_definition_test.dart`
Expected: FAIL — `payroll_sample.dart` / `payrollSchema` / `payrollDefinition` do not exist (compile error).

- [ ] **Step 3: Create `payroll_sample.dart`**

Create `apps/jet_print_playground/lib/payroll_sample.dart` with this exact content:

```dart
/// The playground's payroll sample: a multi-employee **payroll run** —
/// **Employee ▸ Earnings / Deductions** — authored entirely through the
/// library's public API (`package:jet_print/jet_print.dart`), the way an
/// external consumer would.
///
/// It is the first sample to use **two parallel nested collections** (earnings
/// AND deductions) under one master row. Employees are grouped by an outer
/// `department` level and an inner `employee` level; each employee renders a
/// full US-style pay stub: an identity card with a verification QR (spec 036),
/// an Earnings table and a Deductions table (each with a year-to-date column), a
/// highlighted Net Pay box, department subtotals and a company grand total.
///
/// Line-item amounts and the authoritative employee totals (`grossPay`,
/// `totalDeductions`, `netPay`) are both stored: the section footers show the
/// LIVE folds (`SUM($F{earnAmount})` / `SUM($F{dedAmount})`, spec 029) which
/// reconcile to the stored gross/deductions, Net is derived live as
/// `$F{grossPay} - $F{totalDeductions}`, and the department/company totals fold
/// the stored master fields (`SUM($F{grossPay})` …, spec 028). One structural
/// concession to the current engine (a scope renders only one per-row band): the
/// "DEDUCTIONS" heading + its column titles ride at the bottom of the Earnings
/// footer band.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// The payroll data structure: employee master fields plus two nested
/// collections — `earnings` and `deductions`. Attach it via `dataSchema:`.
const JetDataSchema payrollSchema = JetDataSchema(
  name: 'Employee',
  fields: <FieldDef>[
    FieldDef('empNo', type: JetFieldType.string),
    FieldDef('empName', type: JetFieldType.string),
    FieldDef('jobTitle', type: JetFieldType.string),
    FieldDef('department', type: JetFieldType.string),
    FieldDef('payPeriod', type: JetFieldType.string),
    FieldDef('payDate', type: JetFieldType.string),
    FieldDef('payMethod', type: JetFieldType.string),
    FieldDef('verifyToken', type: JetFieldType.string),
    // Authoritative employee-level totals (a payroll system computes these);
    // the live section folds reconcile to gross/deductions and net is derived.
    FieldDef('grossPay', type: JetFieldType.double),
    FieldDef('totalDeductions', type: JetFieldType.double),
    FieldDef('netPay', type: JetFieldType.double),
    FieldDef(
      'earnings',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('type', type: JetFieldType.string),
        FieldDef('hours', type: JetFieldType.double),
        FieldDef('rate', type: JetFieldType.double),
        FieldDef('earnAmount', type: JetFieldType.double),
        FieldDef('earnYtd', type: JetFieldType.double),
      ],
    ),
    FieldDef(
      'deductions',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('type', type: JetFieldType.string),
        FieldDef('dedAmount', type: JetFieldType.double),
        FieldDef('dedYtd', type: JetFieldType.double),
      ],
    ),
  ],
);

/// A muted grey used for captions and secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// A pale accent fill behind the Net Pay figure.
const JetColor _netFill = JetColor(0xFFEAF3EC);

const String _money = '#,##0.00';

/// The payroll report authored in the reified band model (spec 024).
ReportDefinition payrollDefinition() => const ReportDefinition(
      name: 'Payroll',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'runningTitle',
              bounds: JetRect(x: 0, y: 2, width: 300, height: 14),
              text: 'PAYROLL',
              style: JetTextStyle(
                  fontSize: 9, color: _grey, weight: JetFontWeight.bold),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'pageNumber',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 14),
              text: 'Page',
              style: JetTextStyle(
                  fontSize: 9, color: _grey, align: JetTextAlign.right),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT} + "  ·  Confidential  ·  Amounts in USD"',
            ),
          ],
        ),
      ),
      body: ReportBody(
        summary: Band(
          id: 'summary',
          type: BandType.summary,
          height: 52,
          elements: <ReportElement>[
            ShapeElement(
              id: 'grandRule',
              bounds: JetRect(x: 0, y: 4, width: 538, height: 1.5),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _grey),
            ),
            TextElement(
              id: 'capGrandGross',
              bounds: JetRect(x: 196, y: 8, width: 110, height: 10),
              text: 'Gross',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'capGrandDed',
              bounds: JetRect(x: 312, y: 8, width: 110, height: 10),
              text: 'Deductions',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'capGrandNet',
              bounds: JetRect(x: 428, y: 8, width: 110, height: 10),
              text: 'Net',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'grandLabel',
              bounds: JetRect(x: 0, y: 22, width: 190, height: 16),
              text: 'COMPANY TOTAL',
              style: JetTextStyle(weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'grandGross',
              bounds: JetRect(x: 196, y: 22, width: 110, height: 16),
              text: 'grandGross',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'SUM($F{grossPay})',
              format: _money,
            ),
            TextElement(
              id: 'grandDed',
              bounds: JetRect(x: 312, y: 22, width: 110, height: 16),
              text: 'grandDed',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'SUM($F{totalDeductions})',
              format: _money,
            ),
            TextElement(
              id: 'grandNet',
              bounds: JetRect(x: 428, y: 22, width: 110, height: 16),
              text: 'grandNet',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'SUM($F{netPay})',
              format: _money,
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            // --- Outer group: department ---
            GroupLevel(
              id: 'department',
              name: 'department',
              key: r'$F{department}',
              header: Band(
                id: 'deptHeader',
                type: BandType.groupHeader,
                height: 26,
                elements: <ReportElement>[
                  TextElement(
                    id: 'deptName',
                    bounds: JetRect(x: 0, y: 2, width: 538, height: 16),
                    text: 'department',
                    style: JetTextStyle(
                        fontSize: 12, weight: JetFontWeight.bold),
                    expression: r'"DEPARTMENT — " + $F{department}',
                  ),
                  ShapeElement(
                    id: 'deptRule',
                    bounds: JetRect(x: 0, y: 22, width: 538, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                ],
              ),
              footer: Band(
                id: 'deptFooter',
                type: BandType.groupFooter,
                height: 44,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 'deptFooterRule',
                    bounds: JetRect(x: 0, y: 2, width: 538, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                  TextElement(
                    id: 'capDeptGross',
                    bounds: JetRect(x: 196, y: 8, width: 110, height: 10),
                    text: 'Gross',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, align: JetTextAlign.right),
                  ),
                  TextElement(
                    id: 'capDeptDed',
                    bounds: JetRect(x: 312, y: 8, width: 110, height: 10),
                    text: 'Deductions',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, align: JetTextAlign.right),
                  ),
                  TextElement(
                    id: 'capDeptNet',
                    bounds: JetRect(x: 428, y: 8, width: 110, height: 10),
                    text: 'Net',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, align: JetTextAlign.right),
                  ),
                  TextElement(
                    id: 'deptSubLabel',
                    bounds: JetRect(x: 0, y: 22, width: 190, height: 14),
                    text: 'Department subtotal',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'deptGross',
                    bounds: JetRect(x: 196, y: 22, width: 110, height: 14),
                    text: 'deptGross',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{grossPay})',
                    format: _money,
                  ),
                  TextElement(
                    id: 'deptDed',
                    bounds: JetRect(x: 312, y: 22, width: 110, height: 14),
                    text: 'deptDed',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{totalDeductions})',
                    format: _money,
                  ),
                  TextElement(
                    id: 'deptNet',
                    bounds: JetRect(x: 428, y: 22, width: 110, height: 14),
                    text: 'deptNet',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{netPay})',
                    format: _money,
                  ),
                ],
              ),
            ),
            // --- Inner group: employee (one pay stub each) ---
            GroupLevel(
              id: 'employee',
              name: 'employee',
              key: r'$F{empNo}',
              keepTogether: true,
              header: Band(
                id: 'empHeader',
                type: BandType.groupHeader,
                height: 122,
                elements: <ReportElement>[
                  TextElement(
                    id: 'empName',
                    bounds: JetRect(x: 0, y: 0, width: 300, height: 20),
                    text: 'empName',
                    style: JetTextStyle(
                        fontSize: 14, weight: JetFontWeight.bold),
                    expression: r'$F{empName}',
                  ),
                  TextElement(
                    id: 'jobTitle',
                    bounds: JetRect(x: 0, y: 22, width: 300, height: 14),
                    text: 'jobTitle',
                    style: JetTextStyle(color: _grey),
                    expression: r'$F{jobTitle}',
                  ),
                  TextElement(
                    id: 'metaEmpNo',
                    bounds: JetRect(x: 0, y: 42, width: 180, height: 12),
                    text: 'empNo',
                    style: JetTextStyle(fontSize: 9),
                    expression: r'"Emp #: " + $F{empNo}',
                  ),
                  TextElement(
                    id: 'metaPeriod',
                    bounds: JetRect(x: 190, y: 42, width: 268, height: 12),
                    text: 'payPeriod',
                    style: JetTextStyle(fontSize: 9),
                    expression: r'"Pay period: " + $F{payPeriod}',
                  ),
                  TextElement(
                    id: 'metaPayDate',
                    bounds: JetRect(x: 0, y: 58, width: 180, height: 12),
                    text: 'payDate',
                    style: JetTextStyle(fontSize: 9),
                    expression: r'"Pay date: " + $F{payDate}',
                  ),
                  TextElement(
                    id: 'metaPayMethod',
                    bounds: JetRect(x: 190, y: 58, width: 268, height: 12),
                    text: 'payMethod',
                    style: JetTextStyle(fontSize: 9),
                    expression: r'"Pay method: " + $F{payMethod}',
                  ),
                  // Verification QR (top-right). Literal fallback drives the
                  // headless/no-row canvas; the bound field wins for a real row.
                  BarcodeElement(
                    id: 'verifyQr',
                    bounds: JetRect(x: 474, y: 0, width: 64, height: 64),
                    symbology: BarcodeSymbology.qrCode,
                    data: 'PAY-VERIFY',
                    dataField: 'verifyToken',
                  ),
                  TextElement(
                    id: 'verifyCaption',
                    bounds: JetRect(x: 458, y: 66, width: 80, height: 10),
                    text: 'Scan to verify',
                    style: JetTextStyle(
                        fontSize: 7, color: _grey, align: JetTextAlign.center),
                  ),
                  // Earnings section heading + column titles.
                  TextElement(
                    id: 'earningsHeading',
                    bounds: JetRect(x: 0, y: 84, width: 200, height: 14),
                    text: 'EARNINGS',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colEarnType',
                    bounds: JetRect(x: 24, y: 100, width: 180, height: 12),
                    text: 'Earnings',
                    style: JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colEarnHours',
                    bounds: JetRect(x: 212, y: 100, width: 60, height: 12),
                    text: 'Hours',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colEarnRate',
                    bounds: JetRect(x: 278, y: 100, width: 70, height: 12),
                    text: 'Rate',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colEarnCurrent',
                    bounds: JetRect(x: 396, y: 100, width: 70, height: 12),
                    text: 'Current',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colEarnYtd',
                    bounds: JetRect(x: 472, y: 100, width: 66, height: 12),
                    text: 'YTD',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                ],
              ),
              footer: Band(
                id: 'empFooter',
                type: BandType.groupFooter,
                height: 64,
                elements: <ReportElement>[
                  // Net Pay highlight box.
                  ShapeElement(
                    id: 'netBox',
                    bounds: JetRect(x: 300, y: 6, width: 238, height: 40),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(
                        fill: _netFill, stroke: _grey, strokeWidth: 0.75),
                  ),
                  TextElement(
                    id: 'netLabel',
                    bounds: JetRect(x: 312, y: 16, width: 120, height: 18),
                    text: 'NET PAY',
                    style: JetTextStyle(
                        fontSize: 11, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'netValue',
                    bounds: JetRect(x: 408, y: 14, width: 118, height: 22),
                    text: 'netValue',
                    style: JetTextStyle(
                        fontSize: 13,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                    expression: r'$F{grossPay} - $F{totalDeductions}',
                    format: _money,
                  ),
                  TextElement(
                    id: 'confidentialNote',
                    bounds: JetRect(x: 0, y: 50, width: 300, height: 12),
                    text:
                        'This pay statement is confidential to the named employee.',
                    style: JetTextStyle(fontSize: 8, color: _grey),
                  ),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            // --- Earnings table ---
            NestedScope(DetailScope(
              id: 'earnings',
              collectionField: 'earnings',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'earnRow',
                  type: BandType.detail,
                  height: 16,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'earnType',
                      bounds: JetRect(x: 24, y: 1, width: 180, height: 14),
                      text: 'type',
                      expression: r'$F{type}',
                    ),
                    TextElement(
                      id: 'earnHours',
                      bounds: JetRect(x: 212, y: 1, width: 60, height: 14),
                      text: 'hours',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{hours}',
                      format: _money,
                    ),
                    TextElement(
                      id: 'earnRate',
                      bounds: JetRect(x: 278, y: 1, width: 70, height: 14),
                      text: 'rate',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{rate}',
                      format: _money,
                    ),
                    TextElement(
                      id: 'earnCurrent',
                      bounds: JetRect(x: 396, y: 1, width: 70, height: 14),
                      text: 'earnAmount',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{earnAmount}',
                      format: _money,
                    ),
                    TextElement(
                      id: 'earnYtd',
                      bounds: JetRect(x: 472, y: 1, width: 66, height: 14),
                      text: 'earnYtd',
                      style: JetTextStyle(
                          align: JetTextAlign.right, color: _grey),
                      expression: r'$F{earnYtd}',
                      format: _money,
                    ),
                  ],
                )),
              ],
              // Same-scope fold over the employee's earnings (spec 029): gross
              // pay. The "DEDUCTIONS" heading + column titles ride here because a
              // scope renders only one per-row band.
              footer: Band(
                id: 'earningsFooter',
                type: BandType.groupFooter,
                height: 64,
                elements: <ReportElement>[
                  TextElement(
                    id: 'grossLabel',
                    bounds: JetRect(x: 278, y: 2, width: 110, height: 14),
                    text: 'Gross pay',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'grossValue',
                    bounds: JetRect(x: 396, y: 2, width: 70, height: 14),
                    text: 'grossValue',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{earnAmount})',
                    format: _money,
                  ),
                  ShapeElement(
                    id: 'dedRule',
                    bounds: JetRect(x: 0, y: 22, width: 538, height: 0.75),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                  TextElement(
                    id: 'deductionsHeading',
                    bounds: JetRect(x: 0, y: 28, width: 200, height: 14),
                    text: 'DEDUCTIONS',
                    style: JetTextStyle(
                        fontSize: 8, color: _grey, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colDedType',
                    bounds: JetRect(x: 24, y: 48, width: 200, height: 12),
                    text: 'Deductions',
                    style: JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colDedCurrent',
                    bounds: JetRect(x: 396, y: 48, width: 70, height: 12),
                    text: 'Current',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colDedYtd',
                    bounds: JetRect(x: 472, y: 48, width: 66, height: 12),
                    text: 'YTD',
                    style: JetTextStyle(
                        fontSize: 9,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                ],
              ),
            )),
            // --- Deductions table ---
            NestedScope(DetailScope(
              id: 'deductions',
              collectionField: 'deductions',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'dedRow',
                  type: BandType.detail,
                  height: 16,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'dedType',
                      bounds: JetRect(x: 24, y: 1, width: 300, height: 14),
                      text: 'type',
                      expression: r'$F{type}',
                    ),
                    TextElement(
                      id: 'dedCurrent',
                      bounds: JetRect(x: 396, y: 1, width: 70, height: 14),
                      text: 'dedAmount',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{dedAmount}',
                      format: _money,
                    ),
                    TextElement(
                      id: 'dedYtd',
                      bounds: JetRect(x: 472, y: 1, width: 66, height: 14),
                      text: 'dedYtd',
                      style: JetTextStyle(
                          align: JetTextAlign.right, color: _grey),
                      expression: r'$F{dedYtd}',
                      format: _money,
                    ),
                  ],
                )),
              ],
              // Same-scope fold over the employee's deductions (spec 029).
              footer: Band(
                id: 'deductionsFooter',
                type: BandType.groupFooter,
                height: 22,
                elements: <ReportElement>[
                  ShapeElement(
                    id: 'totalDedRule',
                    bounds: JetRect(x: 278, y: 1, width: 260, height: 0.75),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _grey),
                  ),
                  TextElement(
                    id: 'totalDedLabel',
                    bounds: JetRect(x: 278, y: 4, width: 110, height: 14),
                    text: 'Total deductions',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'totalDedValue',
                    bounds: JetRect(x: 396, y: 4, width: 70, height: 14),
                    text: 'totalDedValue',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'SUM($F{dedAmount})',
                    format: _money,
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/payroll_definition_test.dart`
Expected: PASS (all 5 tests). If `validate(...)` is non-empty, read each diagnostic — most likely an aggregate placed outside a legal sink, or an unexpected second per-row band — and fix the offending band before continuing.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/payroll_sample.dart \
        apps/jet_print_playground/test/payroll_definition_test.dart
git commit -m "feat(playground): payroll schema + report definition"
```

---

### Task 2: Sample data + render entry (`rendered_payroll_example.dart`)

**Files:**
- Create: `apps/jet_print_playground/lib/rendered_payroll_example.dart`
- Test: `apps/jet_print_playground/test/rendered_payroll_example_test.dart`

**Interfaces:**
- Consumes: `payrollSchema`, `payrollDefinition()` from Task 1.
- Produces:
  - `const List<Map<String, Object?>> kSamplePayroll` — 4 employees across 2 departments (ordered by department).
  - `JetDataSource payrollDataSource()` → `JetInMemoryDataSource(kSamplePayroll, fields: payrollSchema.fields)`.
  - `RenderedReport renderPayrollDefinition({ReportDefinition? definition, JetDataSource? source, List<JetFontFamily> fonts})`.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/rendered_payroll_example_test.dart`:

```dart
// Rendered payroll example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the run fills cleanly and
// that the live section folds, the net figure, the department subtotals and the
// company grand total all equal the sums of the SAME sample data — so the proof
// and the render can never silently drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation imports for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. rendered_packing_slip_example_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_payroll_example.dart';

final NumberFormat _money = NumberFormat('#,##0.00');

List<Map<String, Object?>> _coll(Map<String, Object?> emp, String key) =>
    (emp[key]! as List<Object?>).cast<Map<String, Object?>>();

double _sum(List<Map<String, Object?>> rows, String field) => rows.fold<double>(
    0, (double s, Map<String, Object?> r) => s + (r[field]! as num));

void main() {
  group('rendered payroll example', () {
    test('has four employees across two departments, ordered by department', () {
      expect(kSamplePayroll, hasLength(4));
      final List<String> depts = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          e['department']! as String,
      ];
      // Sorted-by-department invariant: equal departments are contiguous.
      expect(depts, depts.toSet().toList()..sort((String a, String b) {
        return depts.indexOf(a).compareTo(depts.indexOf(b));
      }).expand((String d) => depts.where((String x) => x == d)).toList());
      expect(depts.toSet(), hasLength(2));
    });

    test('stored employee totals equal the live line-item sums', () {
      for (final Map<String, Object?> e in kSamplePayroll) {
        final double gross = _sum(_coll(e, 'earnings'), 'earnAmount');
        final double ded = _sum(_coll(e, 'deductions'), 'dedAmount');
        expect((e['grossPay']! as num).toDouble(), closeTo(gross, 0.001),
            reason: '${e['empNo']} grossPay equals its earnings sum');
        expect((e['totalDeductions']! as num).toDouble(), closeTo(ded, 0.001),
            reason: '${e['empNo']} totalDeductions equals its deductions sum');
        expect((e['netPay']! as num).toDouble(), closeTo(gross - ded, 0.001),
            reason: '${e['empNo']} netPay equals gross - deductions');
      }
    });

    test('renders cleanly (no error diagnostics)', () {
      final RenderedReport report = renderPayrollDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('per-employee gross / deductions / net equal the live sums', () {
      final RenderedReport report = renderPayrollDefinition();
      final List<String> expectedGross = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money.format(_sum(_coll(e, 'earnings'), 'earnAmount')),
      ];
      final List<String> expectedDed = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money.format(_sum(_coll(e, 'deductions'), 'dedAmount')),
      ];
      final List<String> expectedNet = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money.format((e['grossPay']! as num) - (e['totalDeductions']! as num)),
      ];
      expect(_runsForId(report, 'grossValue'), expectedGross);
      expect(_runsForId(report, 'totalDedValue'), expectedDed);
      expect(_runsForId(report, 'netValue'), expectedNet);
    });

    test('department subtotals and company grand total equal the live sums', () {
      final RenderedReport report = renderPayrollDefinition();

      // Group employees by department in document order.
      final Map<String, List<Map<String, Object?>>> byDept =
          <String, List<Map<String, Object?>>>{};
      for (final Map<String, Object?> e in kSamplePayroll) {
        byDept.putIfAbsent(e['department']! as String, () => <Map<String, Object?>>[]).add(e);
      }
      final List<String> expectedDeptNet = <String>[
        for (final List<Map<String, Object?>> emps in byDept.values)
          _money.format(emps.fold<double>(
              0, (double s, Map<String, Object?> e) => s + (e['netPay']! as num))),
      ];
      expect(_runsForId(report, 'deptNet'), expectedDeptNet);

      final double grandGross = kSamplePayroll.fold<double>(
          0, (double s, Map<String, Object?> e) => s + (e['grossPay']! as num));
      final double grandNet = kSamplePayroll.fold<double>(
          0, (double s, Map<String, Object?> e) => s + (e['netPay']! as num));
      expect(_runsForId(report, 'grandGross'), <String>[_money.format(grandGross)]);
      expect(_runsForId(report, 'grandNet'), <String>[_money.format(grandNet)]);
    });
  });
}

/// The rendered text runs of [elementId], in paint order across all pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendered_payroll_example_test.dart`
Expected: FAIL — `rendered_payroll_example.dart` / `kSamplePayroll` / `renderPayrollDefinition` do not exist (compile error).

- [ ] **Step 3: Create `rendered_payroll_example.dart`**

Create `apps/jet_print_playground/lib/rendered_payroll_example.dart` with this exact content. (The stored `grossPay`/`totalDeductions`/`netPay` equal the line-item sums — the test enforces this; if you edit a line item, update the stored total to match.)

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/rendered_payroll_example_test.dart`
Expected: PASS (all 5 tests). If `deptNet` / `grossValue` mismatches appear, the most likely cause is a group-aggregate scope surprise — inspect the actual rendered runs printed by the failure and confirm the engine scoped the department sum to its members. If a stored total mismatches a line-item sum, correct the data (the line items are authoritative).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/rendered_payroll_example.dart \
        apps/jet_print_playground/test/rendered_payroll_example_test.dart
git commit -m "feat(playground): payroll sample data + render entry"
```

---

### Task 3: Register the tab + localize the label

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart` (imports near lines 12–22; new `ShadTab` after the `makbuz` tab that currently ends ~line 251)
- Modify: `apps/jet_print_playground/lib/l10n/app_en.arb`, `app_de.arb`, `app_tr.arb`
- Modify (generated): `apps/jet_print_playground/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart`, `app_localizations_tr.dart` (regenerated by `flutter gen-l10n`)

**Interfaces:**
- Consumes: `payrollSchema`, `payrollDefinition()` (Task 1); `renderPayrollDefinition(...)` (Task 2); `AppLocalizations.tabPayroll` (this task).
- Produces: a visible "Payroll" tab between Packing slip and List.

- [ ] **Step 1: Add the `tabPayroll` key to the three ARB files**

In `apps/jet_print_playground/lib/l10n/app_en.arb`, add this block immediately after the `tabPackingSlip` block (before the `comingSoon` block):

```json
  "tabPayroll": "Payroll",
  "@tabPayroll": {
    "description": "Tab label for the payroll pay-stub designer demo."
  },

```

In `apps/jet_print_playground/lib/l10n/app_de.arb`, add after the `"tabPackingSlip"` line:

```json
  "tabPayroll": "Gehaltsabrechnung",
```

In `apps/jet_print_playground/lib/l10n/app_tr.arb`, add after the `"tabPackingSlip"` line:

```json
  "tabPayroll": "Bordro",
```

(Match the existing comma/format style in each file — every entry except the last needs a trailing comma.)

- [ ] **Step 2: Regenerate the localizations**

Run: `flutter gen-l10n`
Expected: no errors; `app_localizations.dart` now declares `String get tabPayroll;`, and each `app_localizations_*.dart` overrides it. Verify:

Run: `grep -rn "tabPayroll" lib/l10n/*.dart`
Expected: one abstract getter in `app_localizations.dart` plus one override in each of `_en` / `_de` / `_tr`.

- [ ] **Step 3: Add the imports to `main.dart`**

In `apps/jet_print_playground/lib/main.dart`, in the alphabetized import block (lines ~12–22), add `payroll_sample.dart` after the `packing_slip_sample.dart` import and `rendered_payroll_example.dart` after the `rendered_packing_slip_example.dart` import:

```dart
import 'packing_slip_sample.dart';
import 'payroll_sample.dart';
import 'rendered_barcode_example.dart';
```

```dart
import 'rendered_packing_slip_example.dart';
import 'rendered_payroll_example.dart';
```

- [ ] **Step 4: Add the `ShadTab` after the Packing slip tab**

In `apps/jet_print_playground/lib/main.dart`, find the `makbuz` (Packing slip) `ShadTab` — it ends with `child: Text(l10n.tabPackingSlip),` then `),`. Insert this new tab immediately after that closing `),` and before the `nested-lists` `ShadTab`:

```dart
                ShadTab<String>(
                  value: 'bordro',
                  leading: const Icon(LucideIcons.banknote, size: 16),
                  expandContent: true,
                  // A live designer over a payroll run — Employee ▸ Earnings /
                  // Deductions, employees grouped by department, each a full pay
                  // stub with YTD columns, a verification QR, a highlighted Net
                  // Pay box, department subtotals and a company grand total
                  // (payroll_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: payrollDefinition(),
                      dataSchema: payrollSchema,
                      renderReport: (ReportDefinition def) =>
                          renderPayrollDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabPayroll),
                ),
```

- [ ] **Step 5: Analyze and run the full suite**

Run: `flutter analyze`
Expected: no new issues (`LucideIcons.banknote` resolves; imports used).

Run: `flutter test`
Expected: PASS — the whole playground suite green, including the two new test files.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/lib/l10n/
git commit -m "feat(playground): wire the payroll tab (after packing slip)"
```

---

## Manual verification (after Task 3)

Not a code step — do this once before declaring done (the playground targets macOS desktop):

Run: `cd apps/jet_print_playground && flutter run -d macos`

Confirm: the **Payroll** tab appears after **Packing slip**; selecting it shows the designer + preview; the preview shows two department sections, four pay stubs (each with the QR, Earnings table, Deductions table, YTD columns, and a highlighted Net Pay box), department subtotals, and a company grand total; the language toggle flips the tab label (Payroll → Gehaltsabrechnung → Bordro); the stub stays together across a page break (`keepTogether`).

## Self-Review notes (already reconciled)

- **Spec coverage:** schema + definition (Task 1) ✔; dual nested collections, dept+employee groups, inline aggregates in legal sinks, net arithmetic, QR, net-pay box, page footer, YTD columns (Task 1 code) ✔; deterministic reconciled data + render entry + reconciliation test (Task 2) ✔; tab registration + 3-locale label (Task 3) ✔; manual GUI walk (above) ✔.
- **Type/name consistency:** element ids referenced by tests (`grossValue`, `totalDedValue`, `netValue`, `deptNet`, `grandGross`, `grandNet`, `verifyQr`) all exist in the Task 1 band code; `payrollSchema` / `payrollDefinition` / `kSamplePayroll` / `payrollDataSource` / `renderPayrollDefinition` names match across tasks.
- **Pristine validator:** each scope has ≤1 per-row band; every `SUM` sits in a summary / root-group-footer / nested-scope-footer; net is arithmetic. `validate()` expected empty (asserted in Task 1).
```
