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
                    style:
                        JetTextStyle(fontSize: 12, weight: JetFontWeight.bold),
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
                    style:
                        JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
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
                    style:
                        JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
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
                    style:
                        JetTextStyle(fontSize: 11, weight: JetFontWeight.bold),
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
                      style:
                          JetTextStyle(align: JetTextAlign.right, color: _grey),
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
                    style:
                        JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
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
                      style:
                          JetTextStyle(align: JetTextAlign.right, color: _grey),
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
