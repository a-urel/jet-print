/// A first-class group level: a master-level reset boundary that *owns* its
/// header/footer bands and pagination flags.
///
/// Part of the reified report model (spec 024). Replaces [ReportGroup] +
/// loose `groupHeader`/`groupFooter` bands: the group is a single addressable
/// entity, so its flags have exactly one home (fixing the 023 "same flag on
/// both header and footer band" smell). Variables reference a group by its
/// stable [id] (FR-003a), not its [name].
library;

import 'band.dart';

/// An immutable group definition keyed by [key]; when the key changes between
/// consecutive rows the group "breaks", its [footer] then [header] reprint, and
/// its group-scoped variables reset. Outermost-first within a scope.
class GroupLevel {
  /// Creates a group identified by [id], named [name], keyed by [key].
  const GroupLevel({
    required this.id,
    required this.name,
    required this.key,
    this.header,
    this.footer,
    this.keepTogether = false,
    this.reprintHeaderOnEachPage = false,
    this.startNewPage = false,
  });

  /// Stable identity — **the reference target for `ReportVariable.resetGroup`**
  /// (FR-003a).
  final String id;

  /// Display label only (no longer the reference key).
  final String name;

  /// The grouping-key expression (005a syntax); must parse.
  final String key;

  /// The band printed when the group opens, or null.
  final Band? header;

  /// The band printed when the group closes, or null.
  final Band? footer;

  /// Keep this group's whole instance on one page when it fits a fresh page.
  final bool keepTogether;

  /// Reprint [header] atop each continuation page the group spans.
  final bool reprintHeaderOnEachPage;

  /// Start every instance after the first on a fresh page (the 023 feature, now
  /// owned here).
  final bool startNewPage;

  /// Returns a copy with the given fields replaced.
  GroupLevel copyWith({
    String? id,
    String? name,
    String? key,
    Band? header,
    Band? footer,
    bool? keepTogether,
    bool? reprintHeaderOnEachPage,
    bool? startNewPage,
  }) =>
      GroupLevel(
        id: id ?? this.id,
        name: name ?? this.name,
        key: key ?? this.key,
        header: header ?? this.header,
        footer: footer ?? this.footer,
        keepTogether: keepTogether ?? this.keepTogether,
        reprintHeaderOnEachPage:
            reprintHeaderOnEachPage ?? this.reprintHeaderOnEachPage,
        startNewPage: startNewPage ?? this.startNewPage,
      );

  @override
  bool operator ==(Object other) =>
      other is GroupLevel &&
      other.id == id &&
      other.name == name &&
      other.key == key &&
      other.header == header &&
      other.footer == footer &&
      other.keepTogether == keepTogether &&
      other.reprintHeaderOnEachPage == reprintHeaderOnEachPage &&
      other.startNewPage == startNewPage;

  @override
  int get hashCode => Object.hash(id, name, key, header, footer, keepTogether,
      reprintHeaderOnEachPage, startNewPage);

  @override
  String toString() => 'GroupLevel($id, "$name", key: "$key"'
      '${keepTogether ? ', keepTogether' : ''}'
      '${reprintHeaderOnEachPage ? ', reprintHeaderOnEachPage' : ''}'
      '${startNewPage ? ', startNewPage' : ''})';
}
