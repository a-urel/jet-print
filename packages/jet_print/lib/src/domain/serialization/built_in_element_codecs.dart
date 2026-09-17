/// Convenience registration of the built-in element codecs.
library;

import 'barcode_element_codec.dart';
import 'chart_element_codec.dart';
import 'element_codec.dart';
import 'image_element_codec.dart';
import 'shape_element_codec.dart';
import 'text_element_codec.dart';

/// Registers all element types shipped with the library (`text`, `shape`,
/// `image`, `barcode`, `chart`) into [registry].
///
/// Adding a type means a further `registry.register(...)` call — but every
/// registry the library actually persists through is private and pre-wired:
/// `JetReportFormat._registry` is a never-mutated `static final`, and
/// `element_clone.dart` holds its own private top-level one. Neither
/// [ElementCodecRegistry] nor those instances are exported, so this is
/// open/closed for the library's own code and its white-box tests, not for a
/// host.
///
/// This list is codec-only: it is what the **persistence** paths use
/// (`JetReportFormat`, and the designer's `cloneElement` for duplicate/paste),
/// which need no renderer. It must stay in step with the paired codec+renderer
/// list in `rendering/elements/built_in_element_renderers.dart` — the two
/// cannot be collapsed, because `domain/` may not import `rendering/`. They are
/// pinned against each other by
/// `test/architecture/built_in_element_registration_test.dart`.
void registerBuiltInElementCodecs(ElementCodecRegistry registry) {
  registry
    ..register('text', const TextElementCodec())
    ..register('shape', const ShapeElementCodec())
    ..register('image', const ImageElementCodec())
    ..register('barcode', const BarcodeElementCodec())
    ..register('chart', const ChartElementCodec());
}
