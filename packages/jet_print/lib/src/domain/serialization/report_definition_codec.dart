/// Versioned JSON (de)serialization for [ReportDefinition] — the reified report
/// model (spec 024, schema v2). Constitution V.
///
/// Mirrors the legacy [encodeTemplate]/[decodeTemplate] codec but walks the
/// section tree (furniture + body + scopes) and routes every band's elements
/// through the shared [ElementCodecRegistry]. A document at an older
/// `schemaVersion` is walked forward by [migrations] (the 1→2 flat-bands → tree
/// migration) before parsing.
library;

import '../band.dart';
import '../bool_property.dart';
import '../column_layout.dart';
import '../detail_scope.dart';
import '../group_level.dart';
import '../page_format.dart';
import '../report_band.dart' show BandType;
import '../report_definition.dart';
import '../report_element.dart';
import '../report_parameter.dart';
import '../report_variable.dart';
import '../scope_total.dart';
import 'element_codec.dart';
import 'migration.dart';
import 'report_format_exception.dart';

/// The reified-report schema version this build writes (spec 024).
const int kReportDefinitionSchemaVersion = 2;

/// Encodes [def] to a JSON-safe map, stamping [kReportDefinitionSchemaVersion]
/// and routing each element through [registry].
Map<String, Object?> encodeDefinition(
  ReportDefinition def,
  ElementCodecRegistry registry,
) {
  return <String, Object?>{
    'schemaVersion': kReportDefinitionSchemaVersion,
    'name': def.name,
    'page': def.page.toJson(),
    if (def.parameters.isNotEmpty)
      'parameters': <Object?>[
        for (final ReportParameter p in def.parameters) p.toJson(),
      ],
    if (def.variables.isNotEmpty)
      'variables': <Object?>[
        for (final ReportVariable v in def.variables) v.toJson(),
      ],
    'furniture': _encodeFurniture(def.furniture, registry),
    'body': _encodeBody(def.body, registry),
  };
}

Map<String, Object?> _encodeFurniture(
    PageFurniture f, ElementCodecRegistry registry) {
  return <String, Object?>{
    if (f.pageHeader != null)
      'pageHeader': _encodeBand(f.pageHeader!, registry),
    if (f.pageFooter != null)
      'pageFooter': _encodeBand(f.pageFooter!, registry),
    if (f.columnHeader != null)
      'columnHeader': _encodeBand(f.columnHeader!, registry),
    if (f.columnFooter != null)
      'columnFooter': _encodeBand(f.columnFooter!, registry),
    if (f.background != null)
      'background': _encodeBand(f.background!, registry),
  };
}

Map<String, Object?> _encodeBody(
    ReportBody body, ElementCodecRegistry registry) {
  return <String, Object?>{
    if (body.title != null) 'title': _encodeBand(body.title!, registry),
    if (body.summary != null) 'summary': _encodeBand(body.summary!, registry),
    if (body.noData != null) 'noData': _encodeBand(body.noData!, registry),
    'root': _encodeScope(body.root, registry),
  };
}

Map<String, Object?> _encodeScope(
    DetailScope scope, ElementCodecRegistry registry) {
  return <String, Object?>{
    'id': scope.id,
    if (scope.collectionField != null) 'collectionField': scope.collectionField,
    if (scope.groups.isNotEmpty)
      'groups': <Object?>[
        for (final GroupLevel g in scope.groups) _encodeGroup(g, registry),
      ],
    if (scope.children.isNotEmpty)
      'children': <Object?>[
        for (final ScopeNode node in scope.children)
          _encodeNode(node, registry),
      ],
    if (scope.footer != null) 'footer': _encodeBand(scope.footer!, registry),
    if (scope.totals.isNotEmpty)
      'totals': <Map<String, Object?>>[
        for (final ScopeTotal t in scope.totals)
          <String, Object?>{'name': t.name, 'expression': t.expression},
      ],
  };
}

Map<String, Object?> _encodeNode(
    ScopeNode node, ElementCodecRegistry registry) {
  return switch (node) {
    BandNode(band: final Band b) => <String, Object?>{
        'kind': 'band',
        'band': _encodeBand(b, registry),
      },
    NestedScope(scope: final DetailScope s) => <String, Object?>{
        'kind': 'scope',
        'scope': _encodeScope(s, registry),
      },
  };
}

Map<String, Object?> _encodeGroup(GroupLevel g, ElementCodecRegistry registry) {
  return <String, Object?>{
    'id': g.id,
    'name': g.name,
    'key': g.key,
    if (g.header != null) 'header': _encodeBand(g.header!, registry),
    if (g.footer != null) 'footer': _encodeBand(g.footer!, registry),
    if (g.keepTogether) 'keepTogether': true,
    if (g.reprintHeaderOnEachPage) 'reprintHeaderOnEachPage': true,
    if (g.startNewPage) 'startNewPage': true,
  };
}

Map<String, Object?> _encodeBand(Band band, ElementCodecRegistry registry) {
  return <String, Object?>{
    'id': band.id,
    'type': band.type.name,
    'height': band.height,
    if (band.elements.isNotEmpty)
      'elements': <Object?>[
        for (final ReportElement element in band.elements)
          registry.encode(element),
      ],
    if (band.columnLayout != null) 'columnLayout': band.columnLayout!.toJson(),
    if (band.name != null) 'name': band.name,
    if (band.visible != const BoolProperty()) 'visible': band.visible.toJson(),
  };
}

/// Decodes a report-definition [json] map. Validates `schemaVersion` (fail-fast
/// if missing or newer than this build), walks older documents forward via
/// [migrations], then parses the section tree through [registry].
ReportDefinition decodeDefinition(
  Map<String, Object?> json,
  ElementCodecRegistry registry, {
  List<SchemaMigration> migrations = const <SchemaMigration>[],
}) {
  final Object? rawVersion = json['schemaVersion'];
  if (rawVersion is! int) {
    throw const ReportFormatException(
        'Missing or non-integer "schemaVersion".');
  }
  if (rawVersion > kReportDefinitionSchemaVersion) {
    throw ReportFormatException(
        'Report schemaVersion $rawVersion is newer than this build supports '
        '($kReportDefinitionSchemaVersion).');
  }
  final Map<String, Object?> upgraded =
      rawVersion < kReportDefinitionSchemaVersion
          ? runMigrations(
              json,
              from: rawVersion,
              to: kReportDefinitionSchemaVersion,
              migrations: migrations,
            )
          : json;

  final Object? body = upgraded['body'];
  if (body is! Map) {
    throw const ReportFormatException('"body" must be a JSON object.');
  }
  return ReportDefinition(
    name: upgraded['name']! as String,
    page:
        PageFormat.fromJson((upgraded['page']! as Map).cast<String, Object?>()),
    parameters: _decodeList<ReportParameter>(
        upgraded['parameters'], 'parameters', ReportParameter.fromJson),
    variables: _decodeList<ReportVariable>(
        upgraded['variables'], 'variables', ReportVariable.fromJson),
    furniture: _decodeFurniture(upgraded['furniture'], registry),
    body: _decodeBody(body.cast<String, Object?>(), registry),
  );
}

PageFurniture _decodeFurniture(Object? raw, ElementCodecRegistry registry) {
  if (raw == null) return const PageFurniture();
  if (raw is! Map) {
    throw const ReportFormatException('"furniture" must be a JSON object.');
  }
  final Map<String, Object?> f = raw.cast<String, Object?>();
  return PageFurniture(
    pageHeader: _decodeBandOrNull(f['pageHeader'], registry),
    pageFooter: _decodeBandOrNull(f['pageFooter'], registry),
    columnHeader: _decodeBandOrNull(f['columnHeader'], registry),
    columnFooter: _decodeBandOrNull(f['columnFooter'], registry),
    background: _decodeBandOrNull(f['background'], registry),
  );
}

ReportBody _decodeBody(
    Map<String, Object?> json, ElementCodecRegistry registry) {
  final Object? root = json['root'];
  if (root is! Map) {
    throw const ReportFormatException('body "root" must be a JSON object.');
  }
  return ReportBody(
    title: _decodeBandOrNull(json['title'], registry),
    summary: _decodeBandOrNull(json['summary'], registry),
    noData: _decodeBandOrNull(json['noData'], registry),
    root: _decodeScope(root.cast<String, Object?>(), registry),
  );
}

DetailScope _decodeScope(
    Map<String, Object?> json, ElementCodecRegistry registry) {
  final Object? children = json['children'];
  if (children != null && children is! List) {
    throw const ReportFormatException('scope "children" must be a list.');
  }
  final Object? groups = json['groups'];
  if (groups != null && groups is! List) {
    throw const ReportFormatException('scope "groups" must be a list.');
  }
  return DetailScope(
    id: json['id']! as String,
    collectionField: json['collectionField'] as String?,
    groups: groups == null
        ? const <GroupLevel>[]
        : <GroupLevel>[
            for (final Object? g in groups as List)
              _decodeGroup((g! as Map).cast<String, Object?>(), registry),
          ],
    children: children == null
        ? const <ScopeNode>[]
        : <ScopeNode>[
            for (final Object? n in children as List)
              _decodeNode((n! as Map).cast<String, Object?>(), registry),
          ],
    footer: _decodeBandOrNull(json['footer'], registry),
    totals: _decodeScopeTotals(json['totals']),
  );
}

List<ScopeTotal> _decodeScopeTotals(Object? raw) {
  if (raw == null) return const <ScopeTotal>[];
  if (raw is! List) {
    throw const ReportFormatException('scope "totals" must be a list.');
  }
  return <ScopeTotal>[
    for (final Object? e in raw)
      if (e is! Map)
        throw const ReportFormatException(
            'Each "totals" entry must be a JSON object.')
      else
        ScopeTotal(_requireString(e, 'name'), _requireString(e, 'expression')),
  ];
}

String _requireString(Map<Object?, Object?> entry, String key) {
  final Object? value = entry[key];
  if (value is! String) {
    throw ReportFormatException('A "totals" entry "$key" must be a string.');
  }
  return value;
}

ScopeNode _decodeNode(
    Map<String, Object?> json, ElementCodecRegistry registry) {
  switch (json['kind']) {
    case 'band':
      return BandNode(_decodeBand(
          (json['band']! as Map).cast<String, Object?>(), registry));
    case 'scope':
      return NestedScope(_decodeScope(
          (json['scope']! as Map).cast<String, Object?>(), registry));
    default:
      throw ReportFormatException('Unknown scope-node kind "${json['kind']}".');
  }
}

GroupLevel _decodeGroup(
    Map<String, Object?> json, ElementCodecRegistry registry) {
  return GroupLevel(
    id: json['id']! as String,
    name: json['name']! as String,
    key: json['key']! as String,
    header: _decodeBandOrNull(json['header'], registry),
    footer: _decodeBandOrNull(json['footer'], registry),
    keepTogether: json['keepTogether'] as bool? ?? false,
    reprintHeaderOnEachPage: json['reprintHeaderOnEachPage'] as bool? ?? false,
    startNewPage: json['startNewPage'] as bool? ?? false,
  );
}

Band? _decodeBandOrNull(Object? raw, ElementCodecRegistry registry) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw const ReportFormatException('A band must be a JSON object.');
  }
  return _decodeBand(raw.cast<String, Object?>(), registry);
}

Band _decodeBand(Map<String, Object?> json, ElementCodecRegistry registry) {
  final Object? elements = json['elements'];
  if (elements != null && elements is! List) {
    throw const ReportFormatException('Band "elements" must be a list.');
  }
  return Band(
    id: json['id']! as String,
    type: _parseBandType(json['type']),
    height: (json['height']! as num).toDouble(),
    elements: elements == null
        ? const <ReportElement>[]
        : <ReportElement>[
            for (final Object? element in elements as List)
              registry.decode((element! as Map).cast<String, Object?>()),
          ],
    columnLayout: json['columnLayout'] == null
        ? null
        : ColumnLayout.fromJson(
            (json['columnLayout']! as Map).cast<String, Object?>()),
    name: json['name'] as String?,
    visible: json['visible'] is Map
        ? BoolProperty.fromJson(
            (json['visible']! as Map).cast<String, Object?>())
        : const BoolProperty(),
  );
}

BandType _parseBandType(Object? name) {
  if (name is! String) {
    throw const ReportFormatException('Band "type" must be a string.');
  }
  try {
    return BandType.values.byName(name);
  } on ArgumentError {
    throw ReportFormatException('Unknown band type "$name".');
  }
}

List<T> _decodeList<T>(
  Object? raw,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  if (raw == null) return <T>[];
  if (raw is! List) {
    throw ReportFormatException('"$key" must be a list.');
  }
  return <T>[
    for (final Object? entry in raw)
      if (entry is! Map)
        throw ReportFormatException('Each "$key" entry must be a JSON object.')
      else
        fromJson(entry.cast<String, Object?>()),
  ];
}
