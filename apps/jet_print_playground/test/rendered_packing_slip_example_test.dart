// Rendered packing-slip example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the single shipment fills
// cleanly and that the live per-box subtotals and grand totals equal the sums
// of the SAME sample data the render fills — so the proof and the render can
// never silently drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation imports for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. nested_list_definition_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_packing_slip_example.dart';

void main() {
  group('rendered packing-slip example', () {
    test('ships one shipment with three boxes of items', () {
      expect(kSampleShipment, hasLength(1));
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();
      expect(boxes, hasLength(3));
      // Every item carries the two stored measures and a lot number.
      for (final Map<String, Object?> box in boxes) {
        for (final Map<String, Object?> item
            in (box['items']! as List<Object?>).cast()) {
          expect(item['qtyShipped'], isA<int>());
          expect(item['lineWeight'], isA<num>());
          expect(item['lotNo'], isA<String>());
        }
      }
    });

    test('renders the shipment cleanly (no error diagnostics)', () {
      final RenderedReport report = renderPackingSlipDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason: 'a fully-bound packing slip + matching data renders cleanly',
      );
    });

    test('per-box subtotals equal the live data sums', () {
      final RenderedReport report = renderPackingSlipDefinition();
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();

      final List<String> expectedUnits = <String>[
        for (final Map<String, Object?> box in boxes)
          NumberFormat('#,##0').format(_boxUnits(box)),
      ];
      final List<String> expectedWeight = <String>[
        for (final Map<String, Object?> box in boxes)
          NumberFormat('#,##0.000').format(_boxWeight(box)),
      ];
      expect(_runsForId(report, 'boxUnits'), expectedUnits,
          reason: 'each box footer unit count equals its items\' qty sum');
      expect(_runsForId(report, 'boxWeight'), expectedWeight,
          reason: 'each box footer weight equals its items\' weight sum');
    });

    test('grand totals equal the whole-shipment live sums', () {
      final RenderedReport report = renderPackingSlipDefinition();
      final List<Map<String, Object?>> boxes =
          (kSampleShipment.single['boxes']! as List<Object?>).cast();

      final int totalUnits = boxes.fold<int>(
          0, (int s, Map<String, Object?> b) => s + _boxUnits(b));
      final double totalWeight = boxes.fold<double>(
          0, (double s, Map<String, Object?> b) => s + _boxWeight(b));

      expect(_runsForId(report, 'totalBoxes'),
          <String>[NumberFormat('#,##0').format(boxes.length)]);
      expect(_runsForId(report, 'totalUnits'),
          <String>[NumberFormat('#,##0').format(totalUnits)]);
      expect(_runsForId(report, 'totalWeight'),
          <String>[NumberFormat('#,##0.000').format(totalWeight)]);
    });
  });
}

int _boxUnits(Map<String, Object?> box) =>
    (box['items']! as List<Object?>).cast<Map<String, Object?>>().fold<int>(
        0, (int s, Map<String, Object?> i) => s + (i['qtyShipped']! as int));

double _boxWeight(Map<String, Object?> box) =>
    (box['items']! as List<Object?>).cast<Map<String, Object?>>().fold<double>(
        0, (double s, Map<String, Object?> i) => s + (i['lineWeight']! as num));

/// The rendered text runs of [elementId], in paint order across all pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
