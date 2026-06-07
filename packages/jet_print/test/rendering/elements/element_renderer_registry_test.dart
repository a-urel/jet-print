// ElementRendererRegistry: typeKey dispatch, unknown fallback, last-write-wins.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/unknown_element.dart';
import 'package:jet_print/src/rendering/elements/element_renderer_registry.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';

void main() {
  test('rendererFor returns the registered renderer by typeKey', () {
    final ElementRendererRegistry reg = ElementRendererRegistry()
      ..register('text', const TextElementRenderer());
    const TextElement el = TextElement(
        id: 't', bounds: JetRect(x: 0, y: 0, width: 1, height: 1), text: 'x');
    expect(reg.rendererFor(el), isA<TextElementRenderer>());
  });

  test('rendererFor falls back to the Unknown renderer for an unregistered type',
      () {
    final ElementRendererRegistry reg = ElementRendererRegistry();
    final UnknownElement el = UnknownElement(
        typeKey: 'gizmo', rawJson: <String, Object?>{'type': 'gizmo'});
    expect(reg.rendererFor(el), isA<UnknownElementRenderer>());
  });

  test('register is last-write-wins (built-in override)', () {
    final ElementRendererRegistry reg = ElementRendererRegistry()
      ..register('text', const UnknownElementRenderer())
      ..register('text', const TextElementRenderer());
    const TextElement el = TextElement(
        id: 't', bounds: JetRect(x: 0, y: 0, width: 1, height: 1), text: 'x');
    expect(reg.rendererFor(el), isA<TextElementRenderer>());
  });
}
