// ShapeElementCodec round-trip + forward-compat tests (020 / US3 / C8.1–C8.4).
//
// Known forms must be wire-identical to today (serialized by `.name`, no schema
// bump). An unrecognized form must load as a rectangle while preserving the
// original name in `unknownForm`, and re-serialize that original name — a
// lossless forward-compatible round-trip (FR-009). A deliberate pick clears the
// preserved name and serializes the chosen form.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/report_definition_codec.dart';
import 'package:jet_print/src/domain/serialization/shape_element_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';

void main() {
  const ShapeElementCodec codec = ShapeElementCodec();
  const JetRect bounds = JetRect(x: 4, y: 6, width: 50, height: 30);

  group('C8.1 — every known form round-trips wire-identically', () {
    for (final ShapeKind kind in ShapeKind.values) {
      test('${kind.name} serializes by name and decodes back equal', () {
        final ShapeElement s = ShapeElement(
          id: 's',
          bounds: bounds,
          kind: kind,
          style: const JetBoxStyle(stroke: JetColor.black, strokeWidth: 2),
        );
        final Map<String, Object?> json = codec.toJson(s);
        expect(json['kind'], kind.name, reason: 'serialized by enum name');
        expect(json.containsKey('unknownForm'), isFalse,
            reason: 'unknownForm is never written for a known form');
        expect(codec.fromJson(json), s);
      });
    }
  });

  // 021 / C10 — the UI can now reach the none states and translucent colors;
  // the wire rules they ride are pinned here.
  group('fill/stroke none + alpha wire rules (021 / C10)', () {
    test('null fill/stroke are omitted on write and null on read', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: bounds,
        kind: ShapeKind.rectangle,
        style: JetBoxStyle(strokeWidth: 3),
      );
      final Map<String, Object?> json = codec.toJson(s);
      final Map<String, Object?> style =
          (json['style']! as Map).cast<String, Object?>();
      expect(style.containsKey('fill'), isFalse);
      expect(style.containsKey('stroke'), isFalse);

      final ShapeElement decoded = codec.fromJson(json);
      expect(decoded.style.fill, isNull);
      expect(decoded.style.stroke, isNull);
      expect(decoded, s);
    });

    test('translucent #AARRGGBB fill/stroke round-trip with alpha intact', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: bounds,
        kind: ShapeKind.ellipse,
        style: JetBoxStyle(
          fill: JetColor(0x3300FF00),
          stroke: JetColor(0x80112233),
          strokeWidth: 2,
        ),
      );
      final Map<String, Object?> json = codec.toJson(s);
      final Map<String, Object?> style =
          (json['style']! as Map).cast<String, Object?>();
      expect(style['fill'], '#3300FF00');
      expect(style['stroke'], '#80112233');

      final ShapeElement decoded = codec.fromJson(json);
      expect(decoded.style.fill, const JetColor(0x3300FF00));
      expect(decoded.style.stroke, const JetColor(0x80112233));
    });
  });

  group('C8.2 — pre-feature reports are unchanged; schema not bumped', () {
    test('a line/rectangle serialize exactly as before (no new keys)', () {
      const ShapeElement line = ShapeElement(
        id: 'l',
        bounds: bounds,
        kind: ShapeKind.line,
        flipDiagonal: true,
      );
      final Map<String, Object?> json = codec.toJson(line);
      expect(json['kind'], 'line');
      expect(json['flipDiagonal'], true);
      expect(json.containsKey('unknownForm'), isFalse);
      expect(codec.fromJson(json), line);
    });

    test('the report schema version is not bumped by this feature', () {
      expect(kReportDefinitionSchemaVersion, 2);
    });
  });

  group('C8.3 — an unrecognized form round-trips losslessly', () {
    test('octagon loads as rectangle + unknownForm, re-serializes octagon', () {
      final Map<String, Object?> wire = <String, Object?>{
        'id': 's',
        'bounds': bounds.toJson(),
        'kind': 'octagon', // a form a future version added
        'style': const JetBoxStyle(stroke: JetColor.black).toJson(),
      };
      final ShapeElement loaded = codec.fromJson(wire);
      expect(loaded.kind, ShapeKind.rectangle, reason: 'safe render default');
      expect(loaded.unknownForm, 'octagon', reason: 'original name preserved');

      // Re-serializing writes the ORIGINAL form back — nothing is lost.
      expect(codec.toJson(loaded)['kind'], 'octagon');
      // And a second load is stable.
      expect(codec.fromJson(codec.toJson(loaded)), loaded);
    });
  });

  group('C8.4 — a deliberate pick clears the preserved unknown form', () {
    test('after picking a known form, unknownForm is gone and serialized', () {
      final ShapeElement loaded = codec.fromJson(<String, Object?>{
        'id': 's',
        'bounds': bounds.toJson(),
        'kind': 'octagon',
      });
      // Simulate the gallery pick (what SetShapeKindCommand applies).
      final ShapeElement picked =
          loaded.copyWith(kind: ShapeKind.star, clearUnknownForm: true);
      final Map<String, Object?> json = codec.toJson(picked);
      expect(json['kind'], 'star');
      expect(json.containsKey('unknownForm'), isFalse);
      expect(codec.fromJson(json).kind, ShapeKind.star);
      expect(codec.fromJson(json).unknownForm, isNull);
    });
  });

  group('new forms round-trip + unknown-name still degrades (block arrows)',
      () {
    test('roundRect serializes by name and decodes back equal', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: JetRect(x: 4, y: 6, width: 50, height: 30),
        kind: ShapeKind.roundRect,
        style: JetBoxStyle(stroke: JetColor.black, strokeWidth: 2),
      );
      final Map<String, Object?> json = codec.toJson(s);
      expect(json['kind'], 'roundRect');
      expect(codec.fromJson(json), s);
    });

    test('an unknown future form name still loads as rectangle, name preserved',
        () {
      final Map<String, Object?> json = codec.toJson(const ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        kind: ShapeKind.rectangle,
      ));
      json['kind'] = 'someFutureArrow';
      final ShapeElement decoded = codec.fromJson(json);
      expect(decoded.kind, ShapeKind.rectangle);
      expect(decoded.unknownForm, 'someFutureArrow');
      expect(codec.toJson(decoded)['kind'], 'someFutureArrow');
    });
  });
}
