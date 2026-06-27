/// Registers the built-in element types (codec + renderer) shipped with the
/// library, through the single paired `ElementTypeRegistry.register` call so each
/// built-in flows the same path a custom type does (spec 007a). Consumers add
/// their own types with further `register(...)` calls.
library;

import '../../domain/elements/barcode_element.dart';
import '../../domain/elements/chart_element.dart';
import '../../domain/elements/image_element.dart';
import '../../domain/elements/shape_element.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/serialization/barcode_element_codec.dart';
import '../../domain/serialization/chart_element_codec.dart';
import '../../domain/serialization/image_element_codec.dart';
import '../../domain/serialization/shape_element_codec.dart';
import '../../domain/serialization/text_element_codec.dart';
import 'element_type_registry.dart';
import 'renderers/barcode_element_renderer.dart';
import 'renderers/chart_element_renderer.dart';
import 'renderers/image_element_renderer.dart';
import 'renderers/shape_element_renderer.dart';
import 'renderers/text_element_renderer.dart';

/// Registers `text`, `shape`, `image`, `barcode`, and `chart` (each codec paired
/// with its renderer) into [registry].
void registerBuiltInElementTypes(ElementTypeRegistry registry) {
  registry
    ..register<TextElement>(
        'text', const TextElementCodec(), const TextElementRenderer())
    ..register<ShapeElement>(
        'shape', const ShapeElementCodec(), const ShapeElementRenderer())
    ..register<ImageElement>(
        'image', const ImageElementCodec(), const ImageElementRenderer())
    ..register<BarcodeElement>(
        'barcode', const BarcodeElementCodec(), const BarcodeElementRenderer())
    ..register<ChartElement>(
        'chart', const ChartElementCodec(), const ChartElementRenderer());
}
