// BarcodeElementRenderer: real symbology (modules + HRI + quiet zone).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_encoder.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_symbol.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

// ---------------------------------------------------------------------------
// Fake encoder — returns a known fixed symbol so tests are deterministic.
// ---------------------------------------------------------------------------

/// Fake encoder that returns a simple two-rect 1D symbol (or a 2×2 matrix 2D).
class _FakeEncoder implements BarcodeEncoder {
  const _FakeEncoder({this.twoD = false, this.failWith});

  final bool twoD;
  final String? failWith; // when non-null, always returns BarcodeInvalid

  @override
  BarcodeEncodeResult encode(
    BarcodeSymbology symbology,
    String value, {
    required double width,
    required double height,
    bool showText = true,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m,
  }) {
    if (failWith != null) return BarcodeInvalid(failWith!);
    if (twoD) {
      final double side = width < height ? width : height;
      return BarcodeEncoded(
        BarcodeSymbol(
          modules: [
            BarcodeModule(0, 0, side * 0.5, side * 0.5),
            BarcodeModule(side * 0.5, side * 0.5, side * 0.5, side * 0.5),
          ],
          texts: [],
          spaceWidth: side,
          spaceHeight: side,
          isTwoD: true,
        ),
        twoD ? BarcodeSymbology.qrCode : BarcodeSymbology.code128,
      );
    }
    // 1D: two bars + optional HRI
    final List<BarcodeHriText> texts = showText
        ? [
            BarcodeHriText(
              left: 0,
              top: height * 0.8,
              width: width,
              height: height * 0.2,
              text: value,
              align: BarcodeHriAlign.center,
            ),
          ]
        : [];
    return BarcodeEncoded(
      BarcodeSymbol(
        modules: [
          BarcodeModule(0, 0, width * 0.1, height * 0.8),
          BarcodeModule(width * 0.2, 0, width * 0.05, height * 0.8),
        ],
        texts: texts,
        spaceWidth: width,
        spaceHeight: height,
        isTwoD: false,
      ),
      BarcodeSymbology.code128,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final RenderContext ctx = RenderContext(
    measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));

FrameBuilder freshBuilder() => FrameBuilder(PageFormat.a4Portrait);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Legacy / measure tests that still apply
  // -------------------------------------------------------------------------

  test('measure returns the authored box size', () {
    const BarcodeElementRenderer renderer = BarcodeElementRenderer();
    const BarcodeElement el = BarcodeElement(
        id: 'b',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 30),
        symbology: BarcodeSymbology.code128,
        data: '123');
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(80, 30));
  });

  // -------------------------------------------------------------------------
  // Module rendering
  // -------------------------------------------------------------------------

  test('valid data emits filled RectPrimitives in the bar color', () {
    final renderer = BarcodeElementRenderer(encoder: const _FakeEncoder());
    const bounds = JetRect(x: 10, y: 10, width: 160, height: 80);
    const el = BarcodeElement(
      id: 'b1',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: 'ABC-123',
      color: JetColor(0xFF000080),
      quietZone: false,
    );
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    final rects = frame.primitives.whereType<RectPrimitive>().toList();
    expect(rects, isNotEmpty);
    expect(rects.every((r) => r.fill == const JetColor(0xFF000080)), isTrue);
    // bars stay within bounds (with a small floating-point tolerance)
    for (final r in rects) {
      expect(r.bounds.x >= bounds.x - 0.001, isTrue);
      expect(r.bounds.x + r.bounds.width <= bounds.x + bounds.width + 0.001,
          isTrue);
    }
  });

  test('RectPrimitives carry the element id', () {
    final renderer = BarcodeElementRenderer(encoder: const _FakeEncoder());
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 40);
    const el = BarcodeElement(
        id: 'my-id',
        bounds: bounds,
        symbology: BarcodeSymbology.code128,
        data: 'X',
        quietZone: false);
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final rects = out.build().primitives.whereType<RectPrimitive>().toList();
    expect(rects.every((r) => r.elementId == 'my-id'), isTrue);
  });

  // -------------------------------------------------------------------------
  // HRI text
  // -------------------------------------------------------------------------

  test('showText=true emits a TextRunPrimitive; showText=false omits it', () {
    final renderer = BarcodeElementRenderer(encoder: const _FakeEncoder());
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 40);
    const withText = BarcodeElement(
      id: 'b1',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: '12345',
      showText: true,
      quietZone: false,
    );
    const noText = BarcodeElement(
      id: 'b2',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: '12345',
      showText: false,
      quietZone: false,
    );

    final outWith = freshBuilder();
    renderer.emit(withText, ctx, bounds, outWith);
    final textCount =
        outWith.build().primitives.whereType<TextRunPrimitive>().length;

    final outNo = freshBuilder();
    renderer.emit(noText, ctx, bounds, outNo);
    final noTextCount =
        outNo.build().primitives.whereType<TextRunPrimitive>().length;

    expect(textCount, greaterThan(0),
        reason: 'showText=true → HRI run emitted');
    expect(noTextCount, 0, reason: 'showText=false → no HRI run');
  });

  // -------------------------------------------------------------------------
  // Placeholder fallback
  // -------------------------------------------------------------------------

  test('invalid data falls back to placeholder (1 stroked rect + 1 text)', () {
    final renderer = BarcodeElementRenderer(
        encoder: const _FakeEncoder(failWith: 'bad value'));
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 30);
    const el = BarcodeElement(
        id: 'b1',
        bounds: bounds,
        symbology: BarcodeSymbology.ean13,
        data: 'ABC');
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    expect(frame.primitives.whereType<RectPrimitive>().length, 1);
    expect(frame.primitives.whereType<TextRunPrimitive>().length, 1);
    // The placeholder rect has a stroke (outline) and no fill
    final r = frame.primitives.whereType<RectPrimitive>().first;
    expect(r.stroke, isNotNull);
    expect(r.fill, isNull);
  });

  test('empty data with no dataField emits placeholder', () {
    final renderer = BarcodeElementRenderer(encoder: const _FakeEncoder());
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 30);
    const el = BarcodeElement(
        id: 'b1',
        bounds: bounds,
        symbology: BarcodeSymbology.code128,
        data: '');
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    // placeholder = 1 stroked rect + 1 text label
    expect(frame.primitives.whereType<RectPrimitive>().length, 1);
    expect(frame.primitives.whereType<TextRunPrimitive>().length, 1);
  });

  // -------------------------------------------------------------------------
  // Design-time bound-field preview (FR-004)
  // -------------------------------------------------------------------------

  test('bound field with empty data previews as a 2D symbol (not placeholder)',
      () {
    // The fake 2D encoder returns modules for any non-empty value; the renderer
    // encodes el.dataField! as QR when el.data is empty.
    final renderer =
        BarcodeElementRenderer(encoder: const _FakeEncoder(twoD: true));
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 80);
    const el = BarcodeElement(
      id: 'b1',
      bounds: bounds,
      symbology: BarcodeSymbology.auto,
      data: '',
      dataField: 'sku',
      quietZone: false,
    );
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final rects = out.build().primitives.whereType<RectPrimitive>().toList();
    // Many modules, not a single outline placeholder
    expect(rects.length, greaterThan(1));
    // All rects are filled (module bars), not stroked outlines
    expect(rects.every((r) => r.fill != null), isTrue);
  });

  // -------------------------------------------------------------------------
  // Quiet zone
  // -------------------------------------------------------------------------

  test('quietZone=true insets the bars inside the bounds', () {
    final renderer = BarcodeElementRenderer(encoder: const _FakeEncoder());
    const bounds = JetRect(x: 0, y: 0, width: 100, height: 50);
    const elQZ = BarcodeElement(
      id: 'b1',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: 'X',
      quietZone: true,
    );
    const elNoQZ = BarcodeElement(
      id: 'b2',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: 'X',
      quietZone: false,
    );

    final outQZ = freshBuilder();
    renderer.emit(elQZ, ctx, bounds, outQZ);
    final rectsQZ =
        outQZ.build().primitives.whereType<RectPrimitive>().toList();

    final outNoQZ = freshBuilder();
    renderer.emit(elNoQZ, ctx, bounds, outNoQZ);
    final rectsNoQZ =
        outNoQZ.build().primitives.whereType<RectPrimitive>().toList();

    // With quiet zone the leftmost bar starts further right than without.
    final double minXWithQZ =
        rectsQZ.map((r) => r.bounds.x).reduce((a, b) => a < b ? a : b);
    final double minXNoQZ =
        rectsNoQZ.map((r) => r.bounds.x).reduce((a, b) => a < b ? a : b);
    expect(minXWithQZ, greaterThan(minXNoQZ));
  });

  // -------------------------------------------------------------------------
  // Package encoder integration smoke test
  // -------------------------------------------------------------------------

  test('package encoder: valid Code128 emits filled rects', () {
    // Uses the real PackageBarcodeEncoder (injected as default).
    const renderer = BarcodeElementRenderer();
    const bounds = JetRect(x: 0, y: 0, width: 160, height: 80);
    const el = BarcodeElement(
      id: 'b1',
      bounds: bounds,
      symbology: BarcodeSymbology.code128,
      data: 'ABC-123',
      quietZone: false,
    );
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final rects = out.build().primitives.whereType<RectPrimitive>().toList();
    expect(rects, isNotEmpty);
    expect(rects.every((r) => r.fill != null), isTrue);
  });

  test('package encoder: invalid EAN-13 data falls back to placeholder', () {
    const renderer = BarcodeElementRenderer();
    const bounds = JetRect(x: 0, y: 0, width: 80, height: 40);
    const el = BarcodeElement(
        id: 'b1',
        bounds: bounds,
        symbology: BarcodeSymbology.ean13,
        data: 'ABC');
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    expect(frame.primitives.whereType<RectPrimitive>().length, 1);
    expect(frame.primitives.whereType<TextRunPrimitive>().length, 1);
  });
}
