/// Where an [ImageElement] gets its bytes from (pure Dart).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../value_equality.dart';

/// How an image is scaled to fit its element bounds.
enum JetBoxFit { contain, cover, fill, none }

/// The source of an image: a network [UrlImageSource], a data-bound
/// [FieldImageSource] (resolved at fill time, spec 005), or embedded
/// [BytesImageSource] (base64 in JSON, fully portable). Tagged by a `kind` key.
sealed class JetImageSource {
  /// Const base constructor.
  const JetImageSource();

  /// Reads a [JetImageSource] from its [toJson] map (dispatch on `kind`).
  factory JetImageSource.fromJson(Map<String, Object?> json) {
    final Object? kind = json['kind'];
    switch (kind) {
      case 'url':
        return UrlImageSource(json['url']! as String);
      case 'field':
        return FieldImageSource(json['field']! as String);
      case 'bytes':
        return BytesImageSource(base64Decode(json['base64']! as String));
      default:
        throw FormatException('Unknown image source kind "$kind".');
    }
  }

  /// Serializes to a JSON-safe map including the `kind` discriminator.
  Map<String, Object?> toJson();
}

/// An image fetched from a network [url] at render time.
class UrlImageSource extends JetImageSource with ValueEquality {
  /// Creates a URL image source.
  const UrlImageSource(this.url);

  /// The http(s) URL.
  final String url;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'url', 'url': url};

  @override
  List<Object?> get props => <Object?>[url];
}

/// An image whose bytes come from a data [field], resolved at fill time.
class FieldImageSource extends JetImageSource with ValueEquality {
  /// Creates a field-bound image source.
  const FieldImageSource(this.field);

  /// The data field name.
  final String field;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'field', 'field': field};

  @override
  List<Object?> get props => <Object?>[field];
}

/// An image with [bytes] embedded directly (base64-encoded in JSON).
class BytesImageSource extends JetImageSource with ValueEquality {
  /// Creates an embedded-bytes image source.
  BytesImageSource(this.bytes);

  /// The raw image bytes.
  final Uint8List bytes;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'bytes', 'base64': base64Encode(bytes)};

  @override
  List<Object?> get props => <Object?>[bytes];
}
