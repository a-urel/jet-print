/// Transitional adapter: legacy [ReportTemplate] → reified [ReportDefinition]
/// (spec 024, Phases 2–3 only).
///
/// While the designer still authors the flat [ReportTemplate], the native
/// engine consumes [ReportDefinition]; this converter feeds the former into the
/// latter so render/preview stay green and **byte-identical**. It is the
/// object-level mirror of the 1→2 JSON migration (`v1_to_v2.dart`) — lossless
/// for every shape the legacy designer can produce — and is **deleted** once the
/// designer authors the tree natively (US2 / T032).
library;

import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/group_level.dart';
import '../../domain/report_band.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_group.dart';
import '../../domain/report_template.dart';
import '../../domain/report_variable.dart';

/// Converts a legacy [template] to the equivalent [ReportDefinition], assigning
/// the same deterministic, path-based ids the 1→2 migration assigns (so a
/// converted template and a migrated v1 document are identical).
ReportDefinition convertTemplate(ReportTemplate template) {
  // Group name → deterministic id, in declared order.
  final Map<String, String> groupIdByName = <String, String>{};
  for (int i = 0; i < template.groups.length; i++) {
    groupIdByName[template.groups[i].name] = 'root/g$i';
  }

  final PageFurniture furniture = PageFurniture(
    pageHeader: _slot(template, BandType.pageHeader, 'furniture/pageHeader'),
    pageFooter: _slot(template, BandType.pageFooter, 'furniture/pageFooter'),
    columnHeader:
        _slot(template, BandType.columnHeader, 'furniture/columnHeader'),
    columnFooter:
        _slot(template, BandType.columnFooter, 'furniture/columnFooter'),
    background: _slot(template, BandType.background, 'furniture/background'),
  );

  final List<GroupLevel> groups = <GroupLevel>[
    for (int i = 0; i < template.groups.length; i++)
      _groupLevel(template, template.groups[i], 'root/g$i'),
  ];

  final List<ScopeNode> children = <ScopeNode>[];
  int childIndex = 0;
  for (final ReportBand band in template.bands) {
    if (band.type != BandType.detail) continue;
    children.add(_detailNode(band, 'root/c$childIndex'));
    childIndex++;
  }

  return ReportDefinition(
    name: template.name,
    page: template.page,
    parameters: template.parameters,
    variables: <ReportVariable>[
      for (final ReportVariable v in template.variables)
        _rewriteResetGroup(v, groupIdByName),
    ],
    furniture: furniture,
    body: ReportBody(
      title: _slot(template, BandType.title, 'body/title'),
      summary: _slot(template, BandType.summary, 'body/summary'),
      noData: _slot(template, BandType.noData, 'body/noData'),
      root: DetailScope(id: 'root', groups: groups, children: children),
    ),
  );
}

Band? _slot(ReportTemplate t, BandType type, String id) {
  for (final ReportBand band in t.bands) {
    if (band.type == type) return _band(band, id, type);
  }
  return null;
}

GroupLevel _groupLevel(ReportTemplate t, ReportGroup g, String groupId) {
  final ReportBand? header = _groupBand(t, BandType.groupHeader, g.name);
  final ReportBand? footer = _groupBand(t, BandType.groupFooter, g.name);
  return GroupLevel(
    id: groupId,
    name: g.name,
    key: g.expression,
    header: header == null
        ? null
        : _band(header, '$groupId/header', BandType.groupHeader),
    footer: footer == null
        ? null
        : _band(footer, '$groupId/footer', BandType.groupFooter),
    keepTogether: g.keepTogether,
    reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
    startNewPage: g.startNewPage,
  );
}

ReportBand? _groupBand(ReportTemplate t, BandType type, String groupName) {
  for (final ReportBand band in t.bands) {
    if (band.type == type && band.group == groupName) return band;
  }
  return null;
}

/// A master-level detail band → a [BandNode]; a `collectionField` detail band →
/// a [NestedScope] whose first child is a [BandNode] for the band's own per-row
/// elements, followed by its nested children (recursively).
ScopeNode _detailNode(ReportBand band, String nodeId) {
  if (band.collectionField == null) {
    return BandNode(_band(band, nodeId, BandType.detail));
  }
  return NestedScope(_detailScope(band, nodeId));
}

DetailScope _detailScope(ReportBand band, String scopeId) {
  final List<ScopeNode> children = <ScopeNode>[
    BandNode(_band(band, '$scopeId/c0', BandType.detail)),
  ];
  for (int j = 0; j < band.children.length; j++) {
    children.add(_detailNode(band.children[j], '$scopeId/c${j + 1}'));
  }
  return DetailScope(
    id: scopeId,
    collectionField: band.collectionField,
    children: children,
  );
}

Band _band(ReportBand band, String id, BandType type) =>
    Band(id: id, type: type, height: band.height, elements: band.elements);

ReportVariable _rewriteResetGroup(
    ReportVariable v, Map<String, String> groupIdByName) {
  final String? reset = v.resetGroup;
  if (reset == null || !groupIdByName.containsKey(reset)) return v;
  return ReportVariable(
    name: v.name,
    expression: v.expression,
    calculation: v.calculation,
    resetScope: v.resetScope,
    resetGroup: groupIdByName[reset],
  );
}
