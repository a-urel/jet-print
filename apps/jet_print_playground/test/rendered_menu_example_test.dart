// Rendered menu example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the run fills cleanly, that
// every item's data-bound photo resolves to real image bytes, that the star
// header logo paints, and that the prices match the SAME sample data.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation import for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. rendered_payroll_example_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show ImagePrimitive, PathPrimitive, TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_menu_example.dart';

final NumberFormat _money = NumberFormat('#,##0.00');

void main() {
  group('rendered menu example', () {
    test('items are ordered so equal categories are contiguous', () {
      final List<String> cats = <String>[
        for (final Map<String, Object?> m in kSampleMenu) m['category']! as String,
      ];
      final List<String> contiguous = cats
          .toSet()
          .expand((String c) => cats.where((String x) => x == c))
          .toList();
      expect(cats, contiguous);
      expect(cats.toSet().length, greaterThanOrEqualTo(2));
    });

    test('every item carries a non-empty base64 photo', () {
      for (final Map<String, Object?> m in kSampleMenu) {
        expect(m['photo'], isA<String>());
        expect((m['photo']! as String), isNotEmpty);
      }
    });

    test('renders cleanly (no error diagnostics)', () {
      final RenderedReport report = renderMenuDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('each item resolves its bound photo to real image bytes', () {
      final RenderedReport report = renderMenuDefinition();
      final List<ImagePrimitive> photos =
          _imagesForId(report, 'itemPhoto').toList();
      // One painted photo per menu item, each with decoded bytes.
      expect(photos, hasLength(kSampleMenu.length));
      for (final ImagePrimitive p in photos) {
        expect(p.bytes, isNotEmpty);
      }
    });

    test('the star header logo paints as a filled path', () {
      final RenderedReport report = renderMenuDefinition();
      final List<PathPrimitive> logos =
          _pathsForId(report, 'brandLogo').toList();
      expect(logos, isNotEmpty);
      expect(logos.first.fill, isNotNull);
      expect(logos.first.commands, isNotEmpty);
    });

    test('prices render the formatted sample values in order', () {
      final RenderedReport report = renderMenuDefinition();
      final List<String> expected = <String>[
        for (final Map<String, Object?> m in kSampleMenu)
          _money.format(m['price']! as num),
      ];
      expect(_runsForId(report, 'itemPrice'), expected);
    });
  });
}

/// The painted image primitives for [elementId], in paint order across pages.
Iterable<ImagePrimitive> _imagesForId(RenderedReport report, String elementId) =>
    <ImagePrimitive>[
      for (int i = 0; i < report.pageCount; i++)
        for (final ImagePrimitive p
            in report.pageAt(i).frame.primitives.whereType<ImagePrimitive>())
          if (p.elementId == elementId) p,
    ];

/// The painted path primitives for [elementId], in paint order across pages.
Iterable<PathPrimitive> _pathsForId(RenderedReport report, String elementId) =>
    <PathPrimitive>[
      for (int i = 0; i < report.pageCount; i++)
        for (final PathPrimitive p
            in report.pageAt(i).frame.primitives.whereType<PathPrimitive>())
          if (p.elementId == elementId) p,
    ];

/// The rendered text runs of [elementId], in paint order across pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
