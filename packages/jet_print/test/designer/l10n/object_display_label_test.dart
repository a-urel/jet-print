import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/l10n/jet_print_localizations_en.dart';
import 'package:jet_print/src/designer/l10n/object_display_label.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

void main() {
  final l10n = JetPrintLocalizationsEn();
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('explicit name wins', () {
    const t = TextElement(id: 't', bounds: r, text: 'hi', name: 'Greeting');
    expect(elementDisplayLabel(t, l10n), 'Greeting');
  });

  test('blank name on text falls back to its text', () {
    const t = TextElement(id: 't', bounds: r, text: 'Subtotal');
    expect(elementDisplayLabel(t, l10n), 'Subtotal');
  });

  test('whitespace-only name is treated as blank', () {
    const t = TextElement(id: 't', bounds: r, text: 'Subtotal', name: '   ');
    expect(elementDisplayLabel(t, l10n), 'Subtotal');
  });

  test('blank text falls back to the type label', () {
    const t = TextElement(id: 't', bounds: r, text: '');
    expect(elementDisplayLabel(t, l10n), l10n.elementTypeText);
  });

  test('non-text element falls back to its type label', () {
    const s = ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle);
    expect(elementDisplayLabel(s, l10n), l10n.elementTypeShape);
  });

  test('band name wins, else type label', () {
    const named = Band(id: 'b', type: BandType.detail, height: 20, name: 'Lines');
    const plain = Band(id: 'b', type: BandType.groupFooter, height: 20);
    expect(bandDisplayLabel(named, l10n), 'Lines');
    expect(bandDisplayLabel(plain, l10n), l10n.bandTypeGroupFooter);
  });
}
