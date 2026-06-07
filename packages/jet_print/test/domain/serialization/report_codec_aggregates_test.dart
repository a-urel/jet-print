// Template round-trip of parameters/variables/groups (spec 005b). No Flutter UI.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/value_type.dart';

ElementCodecRegistry _registry() => ElementCodecRegistry();

const ReportTemplate _rich = ReportTemplate(
  name: 'Sales',
  page: PageFormat.a4Portrait,
  parameters: <ReportParameter>[
    ReportParameter(
        name: 'minAmount', type: JetFieldType.double, defaultValue: 0.0),
  ],
  groups: <ReportGroup>[
    ReportGroup(name: 'category', expression: r'$F{category}'),
  ],
  variables: <ReportVariable>[
    ReportVariable(
      name: 'catTotal',
      expression: r'$F{amount}',
      calculation: JetCalculation.sum,
      resetScope: VariableResetScope.group,
      resetGroup: 'category',
    ),
  ],
);

void main() {
  test('round-trips parameters/variables/groups through real JSON', () {
    final ElementCodecRegistry r = _registry();
    final String wire = jsonEncode(encodeTemplate(_rich, r));
    final ReportTemplate decoded =
        decodeTemplate((jsonDecode(wire) as Map).cast<String, Object?>(), r);
    expect(decoded.parameters, _rich.parameters);
    expect(decoded.groups, _rich.groups);
    expect(decoded.variables, _rich.variables);
    // Stable re-encode.
    expect(encodeTemplate(decoded, r), encodeTemplate(_rich, r));
  });

  test('omits the lists when empty (sparse, backward-compatible)', () {
    const ReportTemplate plain =
        ReportTemplate(name: 'Plain', page: PageFormat.a4Portrait);
    final Map<String, Object?> json = encodeTemplate(plain, _registry());
    expect(json.containsKey('parameters'), isFalse);
    expect(json.containsKey('variables'), isFalse);
    expect(json.containsKey('groups'), isFalse);
  });

  test('an old document without the lists decodes to empty lists', () {
    final Map<String, Object?> v1 = <String, Object?>{
      'schemaVersion': kReportSchemaVersion,
      'name': 'Legacy',
      'page': PageFormat.a4Portrait.toJson(),
      'bands': <Object?>[],
    };
    final ReportTemplate decoded = decodeTemplate(v1, _registry());
    expect(decoded.parameters, isEmpty);
    expect(decoded.variables, isEmpty);
    expect(decoded.groups, isEmpty);
  });

  test('throws ReportFormatException on a malformed variable', () {
    final Map<String, Object?> json = <String, Object?>{
      'schemaVersion': kReportSchemaVersion,
      'name': 'X',
      'page': PageFormat.a4Portrait.toJson(),
      'bands': <Object?>[],
      'variables': <Object?>[
        <String, Object?>{
          'name': 'v',
          'expression': '1',
          'calculation': 'nonsense'
        },
      ],
    };
    expect(() => decodeTemplate(json, _registry()),
        throwsA(isA<ReportFormatException>()));
  });

  test('throws ReportFormatException when a list field is not a list', () {
    final Map<String, Object?> json = <String, Object?>{
      'schemaVersion': kReportSchemaVersion,
      'name': 'X',
      'page': PageFormat.a4Portrait.toJson(),
      'bands': <Object?>[],
      'parameters': 'oops', // not a list
    };
    expect(() => decodeTemplate(json, _registry()),
        throwsA(isA<ReportFormatException>()));
  });
}
