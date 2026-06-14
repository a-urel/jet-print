/// Schema migration 1 → 2: the flat [ReportTemplate] band list becomes the
/// reified [ReportDefinition] section tree (spec 024).
///
/// A pure map→map transform (no domain types, no element decoding — element
/// maps are carried verbatim into their new band positions). Every v1 construct
/// has exactly one v2 home and master-level band order is preserved, so a
/// migrated report renders byte-identically (FR-008). Ids are deterministic and
/// path-based (data-model "Stable id scheme"), so migration output is
/// reproducible and golden-stable.
library;

import '../migration.dart';

/// Upgrades a v1 report-JSON map to the v2 reified-tree shape.
class V1ToV2Migration extends SchemaMigration {
  /// Creates the 1→2 migration.
  V1ToV2Migration();

  @override
  int get fromVersion => 1;

  @override
  Map<String, Object?> upgrade(Map<String, Object?> json) {
    final List<Object?> bands =
        (json['bands'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> groupDefs =
        (json['groups'] as List<Object?>?) ?? const <Object?>[];

    // Group name → deterministic group id, in declared order.
    final Map<String, String> groupIdByName = <String, String>{};
    for (int i = 0; i < groupDefs.length; i++) {
      final Map<String, Object?> gd = _asMap(groupDefs[i]);
      groupIdByName[gd['name']! as String] = 'root/g$i';
    }

    // Furniture (record-blind, per-page): first band of each chrome type.
    final Map<String, Object?> furniture = <String, Object?>{};
    for (final String slot in const <String>[
      'pageHeader',
      'pageFooter',
      'columnHeader',
      'columnFooter',
      'background',
    ]) {
      final Map<String, Object?>? band = _firstOfType(bands, slot);
      if (band != null) {
        furniture[slot] = _bandMap(band, 'furniture/$slot', slot);
      }
    }

    // Body once-bands.
    final Map<String, Object?> body = <String, Object?>{};
    for (final String slot in const <String>['title', 'summary', 'noData']) {
      final Map<String, Object?>? band = _firstOfType(bands, slot);
      if (band != null) {
        body[slot] = _bandMap(band, 'body/$slot', slot);
      }
    }

    // Groups: fold the matching groupHeader/groupFooter bands into each level.
    final List<Map<String, Object?>> groups = <Map<String, Object?>>[];
    for (int i = 0; i < groupDefs.length; i++) {
      final Map<String, Object?> gd = _asMap(groupDefs[i]);
      final String name = gd['name']! as String;
      final String groupId = 'root/g$i';
      final Map<String, Object?>? header =
          _firstGroupBand(bands, 'groupHeader', name);
      final Map<String, Object?>? footer =
          _firstGroupBand(bands, 'groupFooter', name);
      groups.add(<String, Object?>{
        'id': groupId,
        'name': name,
        'key': gd['expression'],
        if (header != null)
          'header': _bandMap(header, '$groupId/header', 'groupHeader'),
        if (footer != null)
          'footer': _bandMap(footer, '$groupId/footer', 'groupFooter'),
        if (gd['keepTogether'] == true) 'keepTogether': true,
        if (gd['reprintHeaderOnEachPage'] == true)
          'reprintHeaderOnEachPage': true,
        if (gd['startNewPage'] == true) 'startNewPage': true,
      });
    }

    // Root children: every master-level `detail` band, in v1 order.
    final List<Map<String, Object?>> children = <Map<String, Object?>>[];
    int childIndex = 0;
    for (final Object? raw in bands) {
      final Map<String, Object?> band = _asMap(raw);
      if (band['type'] != 'detail') continue;
      children.add(_detailNode(band, 'root/c$childIndex'));
      childIndex++;
    }

    body['root'] = <String, Object?>{
      'id': 'root',
      if (groups.isNotEmpty) 'groups': groups,
      if (children.isNotEmpty) 'children': children,
    };

    // Variables: rewrite each group-reset name to the new group id (FR-003a).
    final List<Object?>? rawVars = json['variables'] as List<Object?>?;
    final List<Object?>? variables = rawVars == null
        ? null
        : <Object?>[
            for (final Object? v in rawVars)
              _rewriteResetGroup(_asMap(v), groupIdByName),
          ];

    return <String, Object?>{
      'schemaVersion': 2,
      'name': json['name'],
      'page': json['page'],
      if (json['parameters'] != null) 'parameters': json['parameters'],
      if (variables != null) 'variables': variables,
      'furniture': furniture,
      'body': body,
    };
  }

  /// A master-level detail band → a `BandNode`; a `collectionField` detail band
  /// → a `NestedScope` whose first child is a `BandNode` for the band's own
  /// per-row elements, followed by its nested children (recursively).
  Map<String, Object?> _detailNode(Map<String, Object?> band, String nodeId) {
    if (band['collectionField'] == null) {
      return <String, Object?>{
        'kind': 'band',
        'band': _bandMap(band, nodeId, 'detail'),
      };
    }
    return <String, Object?>{
      'kind': 'scope',
      'scope': _detailScope(band, nodeId),
    };
  }

  Map<String, Object?> _detailScope(Map<String, Object?> band, String scopeId) {
    final List<Map<String, Object?>> children = <Map<String, Object?>>[
      <String, Object?>{
        'kind': 'band',
        'band': _bandMap(band, '$scopeId/c0', 'detail'),
      },
    ];
    final List<Object?> nested =
        (band['children'] as List<Object?>?) ?? const <Object?>[];
    for (int j = 0; j < nested.length; j++) {
      children.add(_detailNode(_asMap(nested[j]), '$scopeId/c${j + 1}'));
    }
    return <String, Object?>{
      'id': scopeId,
      'collectionField': band['collectionField'],
      'children': children,
    };
  }

  Map<String, Object?> _bandMap(
      Map<String, Object?> band, String id, String type) {
    final Object? elements = band['elements'];
    return <String, Object?>{
      'id': id,
      'type': type,
      'height': band['height'],
      if (elements is List && elements.isNotEmpty) 'elements': elements,
    };
  }

  Map<String, Object?>? _firstOfType(List<Object?> bands, String type) {
    for (final Object? raw in bands) {
      final Map<String, Object?> band = _asMap(raw);
      if (band['type'] == type) return band;
    }
    return null;
  }

  Map<String, Object?>? _firstGroupBand(
      List<Object?> bands, String type, String groupName) {
    for (final Object? raw in bands) {
      final Map<String, Object?> band = _asMap(raw);
      if (band['type'] == type && band['group'] == groupName) return band;
    }
    return null;
  }

  Map<String, Object?> _rewriteResetGroup(
      Map<String, Object?> variable, Map<String, String> groupIdByName) {
    final Object? reset = variable['resetGroup'];
    if (reset is String && groupIdByName.containsKey(reset)) {
      return <String, Object?>{...variable, 'resetGroup': groupIdByName[reset]};
    }
    return variable;
  }

  Map<String, Object?> _asMap(Object? raw) =>
      (raw! as Map).cast<String, Object?>();
}
