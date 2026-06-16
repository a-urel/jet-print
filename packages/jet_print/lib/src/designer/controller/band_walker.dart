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
import '../../domain/report_band.dart' show BandType;
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
        // A nested scope's footer is a band too (spec 029) — map it through
        // [transform], and preserve the scope's published totals (spec 030):
        // both were silently dropped when this rebuilt the scope field-by-field.
        footer: slot(s.footer),
        totals: s.totals,
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

/// Replaces the element with id [elementId] — in whatever band holds it — by
/// mapping it through [transform], leaving its band's other elements and order
/// intact. The single primitive behind the element-mutation commands (set text,
/// style, binding, format, …); a [transform] that returns its argument
/// unchanged (e.g. wrong element type) yields a value-equal definition, which
/// the controller's commit treats as a no-op.
ReportDefinition updateElement(ReportDefinition def, String elementId,
        ReportElement Function(ReportElement) transform) =>
    mapBands(
        def,
        (Band b) => b.elements.any((ReportElement e) => e.id == elementId)
            ? b.copyWith(elements: <ReportElement>[
                for (final ReportElement e in b.elements)
                  if (e.id == elementId) transform(e) else e,
              ])
            : b);

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
        // Group mapping touches no bands, so the scope's footer + published
        // totals pass through unchanged — but they must still be carried over,
        // not dropped by rebuilding the scope field-by-field.
        footer: s.footer,
        totals: s.totals,
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
    if (s.footer != null) out.add(s.footer!);
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

/// Every stable id in [def] — band ids, element ids, scope ids, and group ids.
/// Used to seed collision-free id minting (a new band/group/scope id must not
/// clash with any existing one, FR-004).
Iterable<String> allIds(ReportDefinition def) {
  final List<String> out = <String>[];
  for (final Band b in allBands(def)) {
    out.add(b.id);
    for (final ReportElement e in b.elements) {
      out.add(e.id);
    }
  }
  void walk(DetailScope s) {
    out.add(s.id);
    for (final GroupLevel g in s.groups) {
      out.add(g.id);
    }
    for (final ScopeNode n in s.children) {
      if (n is NestedScope) walk(n.scope);
    }
  }

  walk(def.body.root);
  return out;
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

/// The [DetailScope] that owns band [bandId] — the scope holding it as a per-row
/// [BandNode], or whose group header/footer it is — or null if the band is not
/// in the scope tree (furniture or a body once-band live outside it).
DetailScope? findScopeOfBand(ReportDefinition def, String bandId) {
  DetailScope? search(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      if (g.header?.id == bandId || g.footer?.id == bandId) return s;
    }
    if (s.footer?.id == bandId) return s;
    for (final ScopeNode n in s.children) {
      switch (n) {
        case BandNode(band: final Band b):
          if (b.id == bandId) return s;
        case NestedScope(scope: final DetailScope inner):
          final DetailScope? found = search(inner);
          if (found != null) return found;
      }
    }
    return null;
  }

  return search(def.body.root);
}

/// The [GroupLevel] whose header or footer is band [bandId], or null when the
/// band is not a group band. Lets the Properties panel resolve a band's group
/// from its position alone — no role inference from `type` + group name.
GroupLevel? findGroupOfBand(ReportDefinition def, String bandId) {
  GroupLevel? search(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      if (g.header?.id == bandId || g.footer?.id == bandId) return g;
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

/// The chain of scopes from the root down to (and including) the scope that
/// owns band [bandId], outermost-first. Empty when the band is not in the scope
/// tree (furniture / once-bands, which resolve against the root/master schema).
/// Used to compute the data fields in scope for a band (each scope's
/// `collectionField` descends the schema one level).
List<DetailScope> scopePathToBand(ReportDefinition def, String bandId) {
  final List<DetailScope> result = <DetailScope>[];
  bool search(DetailScope s, List<DetailScope> trail) {
    final List<DetailScope> here = <DetailScope>[...trail, s];
    for (final GroupLevel g in s.groups) {
      if (g.header?.id == bandId || g.footer?.id == bandId) {
        result.addAll(here);
        return true;
      }
    }
    if (s.footer?.id == bandId) {
      result.addAll(here);
      return true;
    }
    for (final ScopeNode n in s.children) {
      switch (n) {
        case BandNode(band: final Band b):
          if (b.id == bandId) {
            result.addAll(here);
            return true;
          }
        case NestedScope(scope: final DetailScope inner):
          if (search(inner, here)) return true;
      }
    }
    return false;
  }

  search(def.body.root, const <DetailScope>[]);
  return result;
}

/// The chain of scopes from the root down to (and including) the scope with id
/// [scopeId], outermost-first. Empty when no scope matches. Lets the designer
/// compute a nested scope's parent field scope (its valid collection bindings).
List<DetailScope> scopePathToScope(ReportDefinition def, String scopeId) {
  final List<DetailScope> result = <DetailScope>[];
  bool search(DetailScope s, List<DetailScope> trail) {
    final List<DetailScope> here = <DetailScope>[...trail, s];
    if (s.id == scopeId) {
      result.addAll(here);
      return true;
    }
    for (final ScopeNode n in s.children) {
      if (n is NestedScope && search(n.scope, here)) return true;
    }
    return false;
  }

  search(def.body.root, const <DetailScope>[]);
  return result;
}

/// Applies [transform] to **every** [DetailScope] in [def] (bottom-up: each
/// scope's nested children are rebuilt before the scope itself is transformed),
/// returning a new definition. The single place structural scope edits — adding
/// a group/child, removing one — are expressed.
ReportDefinition mapScopes(
    ReportDefinition def, DetailScope Function(DetailScope) transform) {
  DetailScope visit(DetailScope s) {
    final List<ScopeNode> children = <ScopeNode>[
      for (final ScopeNode n in s.children)
        switch (n) {
          BandNode() => n,
          NestedScope(scope: final DetailScope inner) =>
            NestedScope(visit(inner)),
        },
    ];
    return transform(s.copyWith(children: children));
  }

  return def.copyWith(body: def.body.copyWith(root: visit(def.body.root)));
}

/// Appends [group] to scope [scopeId]'s group levels. A no-op if no scope
/// matches.
ReportDefinition addGroup(
        ReportDefinition def, String scopeId, GroupLevel group) =>
    mapScopes(
        def,
        (DetailScope s) => s.id == scopeId
            ? s.copyWith(groups: <GroupLevel>[...s.groups, group])
            : s);

/// Removes the group [groupId] from whichever scope owns it. A no-op if absent.
ReportDefinition removeGroup(ReportDefinition def, String groupId) => mapScopes(
    def,
    (DetailScope s) => s.groups.any((GroupLevel g) => g.id == groupId)
        ? s.copyWith(
            groups: <GroupLevel>[
              for (final GroupLevel g in s.groups)
                if (g.id != groupId) g,
            ],
          )
        : s);

/// Appends [child] to scope [scopeId]'s children. A no-op if no scope matches.
ReportDefinition addScopeChild(
        ReportDefinition def, String scopeId, ScopeNode child) =>
    mapScopes(
        def,
        (DetailScope s) => s.id == scopeId
            ? s.copyWith(children: <ScopeNode>[...s.children, child])
            : s);

/// Removes the nested scope [scopeId] from its parent's children. A no-op if
/// absent.
ReportDefinition removeScope(ReportDefinition def, String scopeId) => mapScopes(
    def,
    (DetailScope s) => s.copyWith(
          children: <ScopeNode>[
            for (final ScopeNode n in s.children)
              if (!(n is NestedScope && n.scope.id == scopeId)) n,
          ],
        ));

// --- Band lifecycle slot helpers (spec 024 / US3 / FR-012) -----------------

/// Whether [type] names a record-blind furniture slot (a page-level singleton).
bool isFurnitureType(BandType type) =>
    type == BandType.pageHeader ||
    type == BandType.pageFooter ||
    type == BandType.columnHeader ||
    type == BandType.columnFooter ||
    type == BandType.background;

/// Whether [type] names a body once-band slot (title / summary / no-data).
bool isOnceType(BandType type) =>
    type == BandType.title ||
    type == BandType.summary ||
    type == BandType.noData;

/// Whether [type] occupies a single slot addressable by type alone (furniture
/// or a body once-band) — the slots band add/remove/retype target directly.
bool isSingletonSlotType(BandType type) =>
    isFurnitureType(type) || isOnceType(type);

/// The band currently occupying the singleton slot for [type], or null when the
/// slot is empty (or [type] is not a singleton-slot type).
Band? bandInSlot(ReportDefinition def, BandType type) => switch (type) {
      BandType.pageHeader => def.furniture.pageHeader,
      BandType.pageFooter => def.furniture.pageFooter,
      BandType.columnHeader => def.furniture.columnHeader,
      BandType.columnFooter => def.furniture.columnFooter,
      BandType.background => def.furniture.background,
      BandType.title => def.body.title,
      BandType.summary => def.body.summary,
      BandType.noData => def.body.noData,
      _ => null,
    };

/// Sets (or, when [band] is null, clears) the singleton slot for [type]. Builds
/// the container directly so a null [band] genuinely clears the slot (copyWith
/// cannot). A no-op for a non-singleton [type].
ReportDefinition setSlotBand(ReportDefinition def, BandType type, Band? band) {
  if (isFurnitureType(type)) {
    final PageFurniture f = def.furniture;
    return def.copyWith(
      furniture: PageFurniture(
        pageHeader: type == BandType.pageHeader ? band : f.pageHeader,
        pageFooter: type == BandType.pageFooter ? band : f.pageFooter,
        columnHeader: type == BandType.columnHeader ? band : f.columnHeader,
        columnFooter: type == BandType.columnFooter ? band : f.columnFooter,
        background: type == BandType.background ? band : f.background,
      ),
    );
  }
  if (isOnceType(type)) {
    final ReportBody b = def.body;
    return def.copyWith(
      body: ReportBody(
        title: type == BandType.title ? band : b.title,
        summary: type == BandType.summary ? band : b.summary,
        noData: type == BandType.noData ? band : b.noData,
        root: b.root,
      ),
    );
  }
  return def;
}

/// Sets (or, when [band] is null, clears) group [groupId]'s [header]/footer
/// band. Builds the group directly so a null [band] clears the slot.
ReportDefinition setGroupBand(ReportDefinition def, String groupId,
        {required bool header, required Band? band}) =>
    updateGroup(
      def,
      groupId,
      (GroupLevel g) => GroupLevel(
        id: g.id,
        name: g.name,
        key: g.key,
        header: header ? band : g.header,
        footer: header ? g.footer : band,
        keepTogether: g.keepTogether,
        reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
        startNewPage: g.startNewPage,
      ),
    );

/// Removes the band with id [bandId] wherever it lives — a furniture slot, a
/// body once-band, a group header/footer, or a scope per-row [BandNode] —
/// returning the new definition. A no-op if no band matches.
ReportDefinition removeBandFromTree(ReportDefinition def, String bandId) {
  final PageFurniture f = def.furniture;
  if (f.pageHeader?.id == bandId ||
      f.pageFooter?.id == bandId ||
      f.columnHeader?.id == bandId ||
      f.columnFooter?.id == bandId ||
      f.background?.id == bandId) {
    return def.copyWith(
      furniture: PageFurniture(
        pageHeader: f.pageHeader?.id == bandId ? null : f.pageHeader,
        pageFooter: f.pageFooter?.id == bandId ? null : f.pageFooter,
        columnHeader: f.columnHeader?.id == bandId ? null : f.columnHeader,
        columnFooter: f.columnFooter?.id == bandId ? null : f.columnFooter,
        background: f.background?.id == bandId ? null : f.background,
      ),
    );
  }
  final ReportBody b = def.body;
  if (b.title?.id == bandId ||
      b.summary?.id == bandId ||
      b.noData?.id == bandId) {
    return def.copyWith(
      body: ReportBody(
        title: b.title?.id == bandId ? null : b.title,
        summary: b.summary?.id == bandId ? null : b.summary,
        noData: b.noData?.id == bandId ? null : b.noData,
        root: b.root,
      ),
    );
  }
  // A group header/footer or a scope per-row band: rebuild each scope.
  return mapScopes(def, (DetailScope s) {
    final List<GroupLevel> groups = <GroupLevel>[
      for (final GroupLevel g in s.groups)
        if (g.header?.id == bandId || g.footer?.id == bandId)
          GroupLevel(
            id: g.id,
            name: g.name,
            key: g.key,
            header: g.header?.id == bandId ? null : g.header,
            footer: g.footer?.id == bandId ? null : g.footer,
            keepTogether: g.keepTogether,
            reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
            startNewPage: g.startNewPage,
          )
        else
          g,
    ];
    final List<ScopeNode> children = <ScopeNode>[
      for (final ScopeNode n in s.children)
        if (!(n is BandNode && n.band.id == bandId)) n,
    ];
    return DetailScope(
      id: s.id,
      collectionField: s.collectionField,
      groups: groups,
      children: children,
    );
  });
}

/// Moves the per-row band [bandId] by [delta] positions within scope [scopeId]'s
/// ordered [DetailScope.children] (negative = toward the front), clamped to the
/// list bounds. A no-op if the band isn't a [BandNode] of that scope, or the
/// move clamps to its current position.
ReportDefinition reorderScopeChild(
        ReportDefinition def, String scopeId, String bandId, int delta) =>
    mapScopes(def, (DetailScope s) {
      if (s.id != scopeId) return s;
      final int idx = s.children
          .indexWhere((ScopeNode n) => n is BandNode && n.band.id == bandId);
      if (idx < 0) return s;
      final int target = (idx + delta).clamp(0, s.children.length - 1);
      if (target == idx) return s;
      final List<ScopeNode> children = <ScopeNode>[...s.children];
      final ScopeNode node = children.removeAt(idx);
      children.insert(target, node);
      return DetailScope(
        id: s.id,
        collectionField: s.collectionField,
        groups: s.groups,
        children: children,
      );
    });
