/// Registers the built-in element types (codec + renderer) shipped with the
/// library, through the single paired `ElementTypeRegistry.register` call so each
/// built-in flows the same path an added type does.
///
/// A further `register(...)` call adds a type — but only from inside the
/// package: `ElementTypeRegistry` is not exported and the render chain builds
/// its own, so this is open/closed for library code and white-box tests, not
/// for a host. Same scope as `domain/serialization/built_in_element_codecs.dart`,
/// which this list is pinned against.
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
///
/// Must cover the same type keys as the codec-only
/// `registerBuiltInElementCodecs`, which the persistence paths use; the two are
/// pinned against each other by
/// `test/architecture/built_in_element_registration_test.dart`.
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
