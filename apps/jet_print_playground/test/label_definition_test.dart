// Confirms the label sample is authored as a single 3-column detail band over
// the chunked-rows schema (the supported way to get a 3-across-then-wrap label
// sheet from a top-to-bottom engine), and that it is pristine under the library
// validator — all through `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/label_sample.dart';

void main() {
  group('label sample', () {
    test('is one per-row detail band on a furniture-free root scope', () {
      final ReportDefinition def = labelSampleDefinition();

      // Labels carry no page chrome.
      expect(def.furniture.pageHeader, isNull);
      expect(def.furniture.pageFooter, isNull);

      // The master scope iterates the chunked rows (a root scope carries no
      // collectionField), with exactly one per-row detail band.
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);
      expect(root.children, hasLength(1));
      expect(root.children.single, isA<BandNode>());
      final Band band = (root.children.single as BandNode).band;
      expect(band.type, BandType.detail);
    });

    test('the detail band lays out three address cells side by side', () {
      final Band band =
          (labelSampleDefinition().body.root.children.single as BandNode).band;

      // Each of the three cells contributes a border + four address lines.
      expect(band.elements.whereType<ShapeElement>(), hasLength(labelColumns));
      final List<TextElement> texts =
          band.elements.whereType<TextElement>().toList();
      expect(texts, hasLength(labelColumns * 4));

      // Every cell binds its prefixed name field, and the three cells are at
      // increasing X offsets (laid across the page, not stacked).
      final List<double> nameXs = <double>[];
      for (int i = 0; i < labelColumns; i++) {
        final TextElement name =
            texts.firstWhere((TextElement t) => t.id == 'c${i}Name');
        expect(name.expression, '\$F{c${i}Name}');
        nameXs.add(name.bounds.x);
      }
      expect(nameXs[0] < nameXs[1] && nameXs[1] < nameXs[2], isTrue,
          reason: 'cells are laid across the page at rising X offsets');
    });

    test('the schema declares four fields per cell', () {
      expect(labelSchema.fields, hasLength(labelColumns * 4));
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(labelSampleDefinition()), isEmpty);
    });
  });
}
