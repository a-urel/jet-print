// The Custom watchlist example: proves the onElementPrint host hook performs
// conditional formatting from raw row data — gain rows render a green up arrow,
// loss rows a red down arrow, flat rows a grey dash, and the change value is
// recoloured to match. The arrow is a ShapeElement (block arrow), not a text
// glyph, so it draws as engine geometry and never depends on font coverage.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show
        FramePrimitive,
        LinePrimitive,
        PathPrimitive,
        RectPrimitive,
        TextRunPrimitive;
import 'package:jet_print_playground/custom_onprint_sample.dart';

const int _up = 0xFF1B873F;
const int _down = 0xFFD32F2F;
const int _grey = 0xFF888888;

/// Every primitive for [elementId] across all pages, in print (row) order.
List<FramePrimitive> _prims(RenderedReport r, String elementId) =>
    <FramePrimitive>[
      for (int i = 0; i < r.pageCount; i++)
        for (final FramePrimitive p in r.pageAt(i).frame.primitives)
          if (p.elementId == elementId) p,
    ];

/// The fill/stroke colour of whatever primitive a shape emitted this row.
int _color(FramePrimitive p) => switch (p) {
      PathPrimitive(:final JetColor? fill) => fill!.argb,
      RectPrimitive(:final JetColor? fill) => fill!.argb,
      LinePrimitive(:final JetColor color) => color.argb,
      TextRunPrimitive(:final JetTextStyle style) => style.color.argb,
      _ => throw StateError('unexpected primitive ${p.runtimeType}'),
    };

void main() {
  group('custom onElementPrint example', () {
    test('renders without error diagnostics', () {
      final RenderedReport r = renderCustomOnPrintDefinition();
      expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('a block arrow is drawn only on a move, coloured by direction', () {
      final RenderedReport r = renderCustomOnPrintDefinition();
      final List<FramePrimitive> arrows = _prims(r, 'changeArrow');
      // Six of the eight tickers move (+,-,+,-,+,+); the two flats suppress the
      // arrow, so only six PATH arrows are drawn.
      expect(arrows.length, 6);
      expect(arrows.every((FramePrimitive p) => p is PathPrimitive), isTrue);
      expect(
          arrows.map(_color).toList(), <int>[_up, _down, _up, _down, _up, _up]);
    });

    test('a thin grey dash is drawn only on the two flat rows', () {
      final RenderedReport r = renderCustomOnPrintDefinition();
      final List<FramePrimitive> dashes = _prims(r, 'changeFlat');
      expect(dashes.length, 2); // INIT and TYRL
      expect(dashes.every((FramePrimitive p) => p is RectPrimitive), isTrue);
      expect(dashes.map(_color).toSet(), <int>{_grey});
      // The dash keeps its authored 2px height — proof the marker is a separate
      // thin element, not the arrow box (whose height the hook cannot shrink).
      for (final FramePrimitive p in dashes) {
        expect(p.bounds.height, 2);
      }
    });

    test('change value is recoloured to match direction', () {
      final RenderedReport r = renderCustomOnPrintDefinition();
      final List<int> colors = _prims(r, 'changeValue').map(_color).toList();
      expect(colors, <int>[_up, _down, _grey, _up, _down, _up, _grey, _up]);
    });

    test('without the hook the arrow keeps its static line placeholder', () {
      // Render the same definition with NO onElementPrint: the formatting is
      // opt-in, so the arrow stays the design-time grey line and no block arrow
      // (PathPrimitive) is ever drawn.
      final RenderedReport bare = JetReportEngine().renderDefinition(
        customOnPrintDefinition(),
        watchlistDataSource(),
        options: const RenderOptions(locale: Locale('en')),
      );
      final List<FramePrimitive> arrows = _prims(bare, 'changeArrow');
      expect(arrows, isNotEmpty);
      expect(arrows.every((FramePrimitive p) => p is LinePrimitive), isTrue);
      expect(arrows.map(_color).toSet(), <int>{_grey});
      // The wired render, by contrast, draws block-arrow paths.
      final RenderedReport wired = renderCustomOnPrintDefinition();
      expect(
          _prims(wired, 'changeArrow').whereType<PathPrimitive>(), isNotEmpty);
    });
  });
}
