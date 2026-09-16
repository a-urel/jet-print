// The two built-in element registration lists may not drift apart.
//
// The library enumerates its built-in element types twice, and must:
//
//   * `registerBuiltInElementCodecs` (domain) — codecs only. This is what the
//     PERSISTENCE paths use: `JetReportFormat`'s static registry (every save)
//     and the designer's `cloneElement` (duplicate / paste).
//   * `registerBuiltInElementTypes` (rendering) — codec **paired** with
//     renderer under one `register<E>` call, which is what makes a mismatched
//     pair a compile error. This is what the RENDER paths use.
//
// The lists cannot be collapsed into one: `domain/` may not import
// `rendering/` (see layer_boundaries_test.dart), so the paired list can never
// be the single source; and a table-driven list would erase the per-entry `E`
// that `ElementTypeRegistry.register<E>` exists to check. So they stay two
// hand-written lists, and this test is what keeps them honest.
//
// Regression: `chart` shipped in the paired list only. Charts rendered fine,
// and an unregistered type is silent in the two places that degrade
// gracefully — `ElementRendererRegistry` falls back to a placeholder and
// `ElementCodecRegistry.decode` falls back to `UnknownElement` — so the gap
// only surfaced as a throw from `encode`, i.e. on save.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';

Set<String> _codecOnlyKeys() {
  final ElementCodecRegistry registry = ElementCodecRegistry();
  registerBuiltInElementCodecs(registry);
  return registry.typeKeys.toSet();
}

Set<String> _pairedKeys() {
  final ElementTypeRegistry registry = ElementTypeRegistry();
  registerBuiltInElementTypes(registry);
  return registry.codecs.typeKeys.toSet();
}

void main() {
  test('every built-in element type is registered in BOTH registration lists',
      () {
    expect(
      _codecOnlyKeys(),
      equals(_pairedKeys()),
      reason: 'registerBuiltInElementCodecs and registerBuiltInElementTypes '
          'must cover the same type keys. A type missing from the codec-only '
          'list renders correctly but THROWS on save and on designer '
          'duplicate/paste; a type missing from the paired list saves '
          'correctly but draws as the Unknown placeholder.',
    );
  });

  test('the built-in set is non-empty (guards a vacuously passing comparison)',
      () {
    expect(_codecOnlyKeys(), isNotEmpty);
  });
}
