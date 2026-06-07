/// Convenience registration of the built-in element codecs.
library;

import 'barcode_element_codec.dart';
import 'element_codec.dart';
import 'image_element_codec.dart';
import 'shape_element_codec.dart';
import 'text_element_codec.dart';

/// Registers all element types shipped with the library (`text`, `shape`,
/// `image`, `barcode`) into [registry]. Consumers add their own types with
/// further `registry.register(...)` calls (Constitution II — open/closed).
void registerBuiltInElementCodecs(ElementCodecRegistry registry) {
  registry
    ..register('text', const TextElementCodec())
    ..register('shape', const ShapeElementCodec())
    ..register('image', const ImageElementCodec())
    ..register('barcode', const BarcodeElementCodec());
}
