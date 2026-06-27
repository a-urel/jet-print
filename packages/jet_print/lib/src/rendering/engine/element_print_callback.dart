/// The host hook for per-element customization at emit time (spec
/// 2026-06-27). Fired once for every element about to be painted — on preview,
/// export, and print alike, because all three render through
/// `JetReportEngine.renderDefinition`.
library;

import '../../domain/report_band.dart' show BandType;
import '../../domain/report_element.dart';
import '../../expression/value.dart';

/// Read-only context handed to a [JetElementPrintCallback] at emit time.
class ElementPrintContext {
  /// Creates an emit-time context.
  const ElementPrintContext({
    required this.pageNumber,
    required this.pageCount,
    required this.bandType,
    required this.bandName,
    required this.fields,
    required this.variables,
  });

  /// 1-based page index the element is printing on.
  final int pageNumber;

  /// Total resolved page count.
  final int pageCount;

  /// The role of the band this element belongs to.
  final BandType bandType;

  /// The group name for group bands; null for non-group bands and page chrome.
  /// (The fill IR does not carry a band id, so this is group-only.)
  final String? bandName;

  /// The originating row's field values, keyed by field name. Empty for page
  /// chrome and static (rowless) bands — null-check, do not assume presence.
  final Map<String, JetValue> fields;

  /// The variable / running-aggregate snapshot at this band instance.
  final Map<String, JetValue> variables;
}

/// Fired once for every element about to be painted. Return [element] unchanged
/// to pass through, a modified copy of the **same runtime type** to alter it, or
/// null to suppress it. A different-type return is ignored (original painted)
/// and a diagnostic recorded; a throw is contained (original painted).
///
/// The element's bounds are fixed at emit time: changing content that needs more
/// height clips at the existing box rather than reflowing the band
/// (Jasper-faithful). Position (x/y) and width changes are honored.
///
/// MUST be deterministic over (element, context): it runs on every render pass,
/// and preview / export / print are separate passes — a callback that reads a
/// clock, RNG, or live data source makes them diverge.
typedef JetElementPrintCallback = ReportElement? Function(
  ReportElement element,
  ElementPrintContext context,
);
