// Confirms the menu sample is a category-grouped flat list whose detail band
// carries a data-bound food picture, and whose page header carries an embedded
// logo — pristine under the validator. Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/menu_sample.dart';

void main() {
  group('menu sample', () {
    test('schema is a flat menu item with a string photo field', () {
      FieldDef f(String name) =>
          menuSchema.fields.firstWhere((FieldDef e) => e.name == name);
      expect(f('category').type, JetFieldType.string);
      expect(f('name').type, JetFieldType.string);
      expect(f('description').type, JetFieldType.string);
      expect(f('price').type, JetFieldType.double);
      // No image/bytes field type exists; the photo is base64 in a string.
      expect(f('photo').type, JetFieldType.string);
      // Flat: no nested collections.
      expect(menuSchema.fields.any((FieldDef e) => e.type == JetFieldType.collection),
          isFalse);
    });

    test('master rows are grouped by category with one detail band', () {
      final DetailScope root = menuSampleDefinition().body.root;
      // Master scope iterates menu items (no collectionField on root).
      expect(root.collectionField, isNull);
      // One group level, keyed on category.
      expect(root.groups, hasLength(1));
      expect(root.groups.single.key, r'$F{category}');
      expect(root.groups.single.header?.type, BandType.groupHeader);
      // Exactly one per-row detail band (the item card), no nested scopes.
      expect(root.children.whereType<NestedScope>(), isEmpty);
      final List<BandNode> bands = root.children.whereType<BandNode>().toList();
      expect(bands, hasLength(1));
      expect(bands.single.band.type, BandType.detail);
      expect(bands.single.band.id, 'item');
    });

    test('the item photo is an image bound to the photo field', () {
      final Band item = menuSampleDefinition()
          .body
          .root
          .children
          .whereType<BandNode>()
          .single
          .band;
      final ImageElement photo = item.elements
          .firstWhere((ReportElement e) => e.id == 'itemPhoto') as ImageElement;
      expect(photo.source, isA<FieldImageSource>());
      expect((photo.source as FieldImageSource).field, 'photo');
    });

    test('the page header logo is an embedded bytes image', () {
      final Band header = menuSampleDefinition().furniture.pageHeader!;
      final ImageElement logo = header.elements
          .firstWhere((ReportElement e) => e.id == 'brandLogo') as ImageElement;
      expect(logo.source, isA<BytesImageSource>());
      expect((logo.source as BytesImageSource).bytes, isNotEmpty);
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(menuSampleDefinition()), isEmpty);
    });
  });
}
