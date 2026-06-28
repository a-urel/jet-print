// packages/jet_print/lib/src/domain/watermark.dart
/// A report-level watermark: faint text OR image drawn behind every page,
/// rotated by [angleDegrees] and dimmed by [opacity]. Pure domain (no
/// rendering/`dart:ui`). Set [text] OR [imageBytes], not both — if both are
/// non-null, the renderer draws the text (see `buildWatermarkPrimitive`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'elements/image_source.dart';
import 'styles/text_style.dart';

/// An immutable watermark description carried by `PageFurniture.watermark`.
class Watermark {
  /// Creates a watermark. [opacity] is clamped to 0..1. Use [text] for a text
  /// watermark or [imageBytes] for an image watermark.
  const Watermark({
    this.text,
    this.textStyle = JetTextStyle.fallback,
    this.imageBytes,
    this.imageFit = JetBoxFit.contain,
    double opacity = 0.15,
    this.angleDegrees = -45,
  }) : opacity = opacity < 0
            ? 0
            : opacity > 1
                ? 1
                : opacity;

  /// Reads a [Watermark] from its [toJson] map.
  factory Watermark.fromJson(Map<String, Object?> json) => Watermark(
        text: json['text'] as String?,
        textStyle: json['textStyle'] == null
            ? JetTextStyle.fallback
            : JetTextStyle.fromJson(
                (json['textStyle']! as Map).cast<String, Object?>()),
        imageBytes: json['imageBytes'] == null
            ? null
            : base64Decode(json['imageBytes']! as String),
        imageFit: json['imageFit'] == null
            ? JetBoxFit.contain
            : JetBoxFit.values.byName(json['imageFit']! as String),
        opacity: json['opacity'] == null
            ? 0.15
            : (json['opacity']! as num).toDouble(),
        angleDegrees: json['angleDegrees'] == null
            ? -45.0
            : (json['angleDegrees']! as num).toDouble(),
      );

  /// The watermark caption, or null for an image watermark.
  final String? text;

  /// Appearance of [text]. The renderer multiplies the color's alpha by
  /// [opacity].
  final JetTextStyle textStyle;

  /// Encoded image bytes (PNG/JPEG), or null for a text watermark.
  final Uint8List? imageBytes;

  /// How the image fills its centered box.
  final JetBoxFit imageFit;

  /// 0..1; the watermark's overall opacity. 0 draws nothing.
  final double opacity;

  /// Rotation in degrees, about the page center. Default -45 (bottom-left to
  /// top-right).
  final double angleDegrees;

  /// A copy with the given fields replaced. Cannot clear [text]/[imageBytes]
  /// back to null (construct a new [Watermark] for that).
  Watermark copyWith({
    String? text,
    JetTextStyle? textStyle,
    Uint8List? imageBytes,
    JetBoxFit? imageFit,
    double? opacity,
    double? angleDegrees,
  }) =>
      Watermark(
        text: text ?? this.text,
        textStyle: textStyle ?? this.textStyle,
        imageBytes: imageBytes ?? this.imageBytes,
        imageFit: imageFit ?? this.imageFit,
        opacity: opacity ?? this.opacity,
        angleDegrees: angleDegrees ?? this.angleDegrees,
      );

  /// Serializes to a JSON-safe map (image bytes base64; omit-when-null).
  Map<String, Object?> toJson() => <String, Object?>{
        if (text != null) 'text': text,
        'textStyle': textStyle.toJson(),
        if (imageBytes != null) 'imageBytes': base64Encode(imageBytes!),
        'imageFit': imageFit.name,
        'opacity': opacity,
        'angleDegrees': angleDegrees,
      };

  @override
  bool operator ==(Object other) {
    if (other is! Watermark ||
        other.text != text ||
        other.textStyle != textStyle ||
        other.imageFit != imageFit ||
        other.opacity != opacity ||
        other.angleDegrees != angleDegrees) {
      return false;
    }
    final Uint8List? a = imageBytes;
    final Uint8List? b = other.imageBytes;
    if ((a == null) != (b == null)) return false;
    if (a != null && b != null) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, textStyle, imageFit, opacity,
      angleDegrees, imageBytes == null ? null : Object.hashAll(imageBytes!));

  @override
  String toString() => 'Watermark(${text != null ? 'text "$text"' : 'image'}, '
      'opacity: $opacity, angle: $angleDegrees)';
}
