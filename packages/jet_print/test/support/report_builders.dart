// test/support/report_builders.dart
/// Shared [ReportDefinition] builders and body-tree lookups for the
/// controller unit tests, replacing the near-identical private `_report(...)`
/// / `_shape(...)` helpers each file used to carry.
///
/// These tests stand in for an EXTERNAL consumer, so this file imports only
/// the public entry point (`package:jet_print/jet_print.dart`) — never
/// `package:jet_print/src/...` (enforced by encapsulation_test.dart).
library;

import 'package:jet_print/jet_print.dart';

/// A minimal report whose body is a single detail band holding [elements] —
/// the canonical seed for driving one controller mutator against known
/// elements. The defaults ('detail', 120pt, A4 portrait) match what the
/// migrated tests were all building privately; pass the named parameters to
/// vary them without forking the shape.
ReportDefinition oneBandReport({
  List<ReportElement> elements = const <ReportElement>[],
  String name = 'test',
  String bandId = 'detail',
  double bandHeight = 120,
  PageFormat page = PageFormat.a4Portrait,
  BandType type = BandType.detail,
}) =>
    ReportDefinition(
      name: name,
      page: page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: bandId,
              type: type,
              height: bandHeight,
              elements: elements,
            )),
          ],
        ),
      ),
    );

/// The element with [id] among the top-level bands of [controller]'s master
/// scope, cast to [T]. Throws a [StateError] naming the id when the element
/// is absent or is not a [T], so a failed lookup reads as a clear message
/// instead of a bare cast error.
T elementById<T extends ReportElement>(
    JetReportDesignerController controller, String id) {
  final ReportElement element = controller.definition.body.root.children
      .whereType<BandNode>()
      .expand((BandNode n) => n.band.elements)
      .firstWhere(
        (ReportElement e) => e.id == id,
        orElse: () => throw StateError(
            'No element with id "$id" in the top-level bands of the body tree.'),
      );
  if (element is! T) {
    throw StateError(
        'Element "$id" is a ${element.runtimeType}, not the expected $T.');
  }
  return element;
}

/// The top-level band with [id] from [controller]'s body tree. Throws a
/// [StateError] naming the id when no such band exists.
Band bandById(JetReportDesignerController controller, String id) => controller
    .definition.body.root.children
    .whereType<BandNode>()
    .firstWhere(
      (BandNode n) => n.band.id == id,
      orElse: () =>
          throw StateError('No top-level band with id "$id" in the body tree.'),
    )
    .band;
