/// A first-class group level: a master-level reset boundary that *owns* its
/// header/footer bands and pagination flags.
///
/// Part of the reified report model. Replaces [ReportGroup] +
/// loose `groupHeader`/`groupFooter` bands: the group is a single addressable
/// entity, so its flags have exactly one home (fixing the 023 "same flag on
/// both header and footer band" smell). Variables reference a group by its
/// stable [id], not its [name].
library;

import 'band.dart';
import 'copy_support.dart';
import 'value_equality.dart';

/// An immutable group definition keyed by [key]; when the key changes between
/// consecutive rows the group "breaks", its [footer] then [header] reprint, and
/// its group-scoped variables reset. Outermost-first within a scope.
class GroupLevel with ValueEquality {
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

  /// Stable identity — **the reference target for `ReportVariable.resetGroup`**.
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
  ///
  /// [header] and [footer] are nullable slots, so they take a thunk: omit to
  /// preserve, pass `() => band` to replace (`() => null` clears).
  GroupLevel copyWith({
    String? id,
    String? name,
    String? key,
    Band? Function()? header,
    Band? Function()? footer,
    bool? keepTogether,
    bool? reprintHeaderOnEachPage,
    bool? startNewPage,
  }) =>
      GroupLevel(
        id: id ?? this.id,
        name: name ?? this.name,
        key: key ?? this.key,
        header: pick(header, this.header),
        footer: pick(footer, this.footer),
        keepTogether: keepTogether ?? this.keepTogether,
        reprintHeaderOnEachPage:
            reprintHeaderOnEachPage ?? this.reprintHeaderOnEachPage,
        startNewPage: startNewPage ?? this.startNewPage,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        key,
        header,
        footer,
        keepTogether,
        reprintHeaderOnEachPage,
        startNewPage,
      ];

  @override
  String toString() => 'GroupLevel($id, "$name", key: "$key"'
      '${keepTogether ? ', keepTogether' : ''}'
      '${reprintHeaderOnEachPage ? ', reprintHeaderOnEachPage' : ''}'
      '${startNewPage ? ', startNewPage' : ''})';
}
