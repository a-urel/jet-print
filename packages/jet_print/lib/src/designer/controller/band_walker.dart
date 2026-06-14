/// Tree navigation + transformation over a [ReportDefinition] (spec 024).
///
/// The reified model replaces the flat `template.bands` list, so the designer
/// can no longer address a band by integer index or scan one list. These pure
/// helpers are the single place that knows how to walk the furniture + body +
/// scope tree, so commands, panels, the canvas, and id seeding don't each
/// re-implement the recursion. All functions are non-mutating: transforms
/// return a new [ReportDefinition].
library;

import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/group_level.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';

/// Applies [transform] to **every** [Band] in [def] (furniture slots, body
/// once-bands, group headers/footers, and scope band nodes — recursively),
/// returning a new definition with the same structure.
ReportDefinition mapBands(ReportDefinition def, Band Function(Band) transform) {
  Band? slot(Band? b) => b == null ? null : transform(b);

  GroupLevel group(GroupLevel g) => GroupLevel(
        id: g.id,
        name: g.name,
        key: g.key,
        header: slot(g.header),
        footer: slot(g.footer),
        keepTogether: g.keepTogether,
        reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
        startNewPage: g.startNewPage,
      );

  late final DetailScope Function(DetailScope) scope;
  ScopeNode node(ScopeNode n) => switch (n) {
        BandNode(band: final Band b) => BandNode(transform(b)),
        NestedScope(scope: final DetailScope s) => NestedScope(scope(s)),
      };
  scope = (DetailScope s) => DetailScope(
        id: s.id,
        collectionField: s.collectionField,
        groups: <GroupLevel>[for (final GroupLevel g in s.groups) group(g)],
        children: <ScopeNode>[for (final ScopeNode n in s.children) node(n)],
      );

  return def.copyWith(
    furniture: PageFurniture(
      pageHeader: slot(def.furniture.pageHeader),
      pageFooter: slot(def.furniture.pageFooter),
      columnHeader: slot(def.furniture.columnHeader),
      columnFooter: slot(def.furniture.columnFooter),
      background: slot(def.furniture.background),
    ),
    body: ReportBody(
      title: slot(def.body.title),
      summary: slot(def.body.summary),
      noData: slot(def.body.noData),
      root: scope(def.body.root),
    ),
  );
}

/// Replaces the band whose id is [bandId] by mapping it through [transform];
/// every other band is preserved referentially. A no-op if no band matches.
ReportDefinition updateBand(
        ReportDefinition def, String bandId, Band Function(Band) transform) =>
    mapBands(def, (Band b) => b.id == bandId ? transform(b) : b);

/// Applies [transform] to every [GroupLevel] in [def] (currently the master
/// scope's levels; recurses nested scopes too), returning a new definition.
ReportDefinition mapGroups(
    ReportDefinition def, GroupLevel Function(GroupLevel) transform) {
  DetailScope scope(DetailScope s) => DetailScope(
        id: s.id,
        collectionField: s.collectionField,
        groups: <GroupLevel>[for (final GroupLevel g in s.groups) transform(g)],
        children: <ScopeNode>[
          for (final ScopeNode n in s.children)
            switch (n) {
              BandNode() => n,
              NestedScope(scope: final DetailScope inner) =>
                NestedScope(scope(inner)),
            },
        ],
      );
  return def.copyWith(body: def.body.copyWith(root: scope(def.body.root)));
}

/// Replaces the group whose id is [groupId] by mapping it through [transform].
/// A no-op if no group matches.
ReportDefinition updateGroup(ReportDefinition def, String groupId,
        GroupLevel Function(GroupLevel) transform) =>
    mapGroups(def, (GroupLevel g) => g.id == groupId ? transform(g) : g);

/// Every band in [def], in a stable structural order (furniture, body
/// once-bands, then the scope tree). Order is deterministic but not visual —
/// callers that need visual order build it from the structure directly.
Iterable<Band> allBands(ReportDefinition def) sync* {
  final List<Band> out = <Band>[];
  void addScope(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      if (g.header != null) out.add(g.header!);
      if (g.footer != null) out.add(g.footer!);
    }
    for (final ScopeNode n in s.children) {
      switch (n) {
        case BandNode(band: final Band b):
          out.add(b);
        case NestedScope(scope: final DetailScope inner):
          addScope(inner);
      }
    }
  }

  for (final Band? b in <Band?>[
    def.furniture.pageHeader,
    def.furniture.pageFooter,
    def.furniture.columnHeader,
    def.furniture.columnFooter,
    def.furniture.background,
    def.body.title,
    def.body.summary,
    def.body.noData,
  ]) {
    if (b != null) out.add(b);
  }
  addScope(def.body.root);
  yield* out;
}

/// The band with id [bandId], or null.
Band? findBand(ReportDefinition def, String bandId) {
  for (final Band b in allBands(def)) {
    if (b.id == bandId) return b;
  }
  return null;
}

/// The band that contains the element with id [elementId], or null.
Band? findBandOfElement(ReportDefinition def, String elementId) {
  for (final Band b in allBands(def)) {
    for (final ReportElement e in b.elements) {
      if (e.id == elementId) return b;
    }
  }
  return null;
}

/// The [GroupLevel] with id [groupId], or null.
GroupLevel? findGroup(ReportDefinition def, String groupId) {
  GroupLevel? search(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      if (g.id == groupId) return g;
    }
    for (final ScopeNode n in s.children) {
      if (n is NestedScope) {
        final GroupLevel? found = search(n.scope);
        if (found != null) return found;
      }
    }
    return null;
  }

  return search(def.body.root);
}

/// The [DetailScope] with id [scopeId], or null.
DetailScope? findScope(ReportDefinition def, String scopeId) {
  DetailScope? search(DetailScope s) {
    if (s.id == scopeId) return s;
    for (final ScopeNode n in s.children) {
      if (n is NestedScope) {
        final DetailScope? found = search(n.scope);
        if (found != null) return found;
      }
    }
    return null;
  }

  return search(def.body.root);
}
