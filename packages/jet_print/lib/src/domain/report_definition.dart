/// The reified root of a report definition (spec 024) — replaces
/// [ReportTemplate].
///
/// A [ReportDefinition] states every band's role structurally instead of
/// inferring it from `type` + group-name + `collectionField` + position:
///
/// * [furniture] — record-blind, per-page chrome ([PageFurniture]).
/// * [body] — the data-driven content ([ReportBody]): once-bands plus a
///   [DetailScope] tree of first-class groups and ordered scope nodes.
///
/// Pure domain layer: no Flutter UI / rendering / designer imports
/// (`package:flutter/foundation.dart` for `listEquals` only, as elsewhere in
/// the domain seam).
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'band.dart';
import 'detail_scope.dart';
import 'page_format.dart';
import 'report_parameter.dart';
import 'report_variable.dart';

/// Record-blind, per-page chrome. Every slot is laid out against a page-scoped
/// context (`PAGE_NUMBER`/`PAGE_COUNT`/params) with no data row — so a furniture
/// band carries no `$F{}` field bindings (validated). [columnHeader],
/// [columnFooter] and [background] are **reserved** (not laid out yet;
/// multi-column is a future feature).
class PageFurniture {
  /// Creates page furniture with the given (all optional) slots.
  const PageFurniture({
    this.pageHeader,
    this.pageFooter,
    this.columnHeader,
    this.columnFooter,
    this.background,
  });

  /// Laid out at the top of every page.
  final Band? pageHeader;

  /// Laid out at the bottom of every page.
  final Band? pageFooter;

  /// **Reserved** — not laid out (future multi-column).
  final Band? columnHeader;

  /// **Reserved** — not laid out (future multi-column).
  final Band? columnFooter;

  /// **Reserved** — not laid out (future watermark/frame layer).
  final Band? background;

  /// Returns a copy with the given slots replaced.
  PageFurniture copyWith({
    Band? pageHeader,
    Band? pageFooter,
    Band? columnHeader,
    Band? columnFooter,
    Band? background,
  }) =>
      PageFurniture(
        pageHeader: pageHeader ?? this.pageHeader,
        pageFooter: pageFooter ?? this.pageFooter,
        columnHeader: columnHeader ?? this.columnHeader,
        columnFooter: columnFooter ?? this.columnFooter,
        background: background ?? this.background,
      );

  @override
  bool operator ==(Object other) =>
      other is PageFurniture &&
      other.pageHeader == pageHeader &&
      other.pageFooter == pageFooter &&
      other.columnHeader == columnHeader &&
      other.columnFooter == columnFooter &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
      pageHeader, pageFooter, columnHeader, columnFooter, background);

  @override
  String toString() => 'PageFurniture('
      '${<String>[
        if (pageHeader != null) 'pageHeader',
        if (pageFooter != null) 'pageFooter',
        if (columnHeader != null) 'columnHeader',
        if (columnFooter != null) 'columnFooter',
        if (background != null) 'background',
      ].join(', ')})';
}

/// The data-driven content: once-bands plus the master [root] scope.
class ReportBody {
  /// Creates a body over the master [root] scope.
  const ReportBody({
    this.title,
    this.summary,
    this.noData,
    required this.root,
  });

  /// Printed once at report start (no row context).
  final Band? title;

  /// Printed once at report end (final variable snapshot).
  final Band? summary;

  /// Printed instead of details when the data set is empty.
  final Band? noData;

  /// The master/root scope (`collectionField == null`).
  final DetailScope root;

  /// Returns a copy with the given fields replaced.
  ReportBody copyWith({
    Band? title,
    Band? summary,
    Band? noData,
    DetailScope? root,
  }) =>
      ReportBody(
        title: title ?? this.title,
        summary: summary ?? this.summary,
        noData: noData ?? this.noData,
        root: root ?? this.root,
      );

  @override
  bool operator ==(Object other) =>
      other is ReportBody &&
      other.title == title &&
      other.summary == summary &&
      other.noData == noData &&
      other.root == root;

  @override
  int get hashCode => Object.hash(title, summary, noData, root);

  @override
  String toString() => 'ReportBody(${<String>[
        if (title != null) 'title',
        if (summary != null) 'summary',
        if (noData != null) 'noData',
        'root',
      ].join(', ')})';
}

/// An immutable, reified report definition: a named [page] layout with declared
/// [parameters] and [variables], record-blind [furniture], and a data-driven
/// [body]. Serializes to versioned JSON (Constitution V).
class ReportDefinition {
  /// Creates a report definition.
  const ReportDefinition({
    required this.name,
    required this.page,
    this.parameters = const <ReportParameter>[],
    this.variables = const <ReportVariable>[],
    this.furniture = const PageFurniture(),
    required this.body,
  });

  /// Human-readable report name.
  final String name;

  /// The page the report is laid out onto.
  final PageFormat page;

  /// Declared parameters (external inputs resolved by `$P{}`).
  final List<ReportParameter> parameters;

  /// Declared variables (accumulated/derived values resolved by `$V{}`);
  /// a group-scoped variable's `resetGroup` holds a [GroupLevel] id (FR-003a).
  final List<ReportVariable> variables;

  /// Record-blind, per-page chrome.
  final PageFurniture furniture;

  /// The data-driven content.
  final ReportBody body;

  /// Returns a copy with the given fields replaced.
  ReportDefinition copyWith({
    String? name,
    PageFormat? page,
    List<ReportParameter>? parameters,
    List<ReportVariable>? variables,
    PageFurniture? furniture,
    ReportBody? body,
  }) =>
      ReportDefinition(
        name: name ?? this.name,
        page: page ?? this.page,
        parameters: parameters ?? this.parameters,
        variables: variables ?? this.variables,
        furniture: furniture ?? this.furniture,
        body: body ?? this.body,
      );

  @override
  bool operator ==(Object other) =>
      other is ReportDefinition &&
      other.name == name &&
      other.page == page &&
      listEquals(other.parameters, parameters) &&
      listEquals(other.variables, variables) &&
      other.furniture == furniture &&
      other.body == body;

  @override
  int get hashCode => Object.hash(name, page, Object.hashAll(parameters),
      Object.hashAll(variables), furniture, body);

  @override
  String toString() => 'ReportDefinition("$name", $page, '
      '${parameters.length} param(s), ${variables.length} variable(s))';
}
