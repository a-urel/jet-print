import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';

void main() {
  group('PageFormat', () {
    test('round-trips through JSON', () {
      const PageFormat page = PageFormat(
        width: 595.28,
        height: 841.89,
        margins: JetEdgeInsets.all(28.35),
      );
      expect(PageFormat.fromJson(page.toJson()), page);
    });

    test('a4Portrait preset is taller than it is wide', () {
      expect(PageFormat.a4Portrait.height,
          greaterThan(PageFormat.a4Portrait.width));
    });
  });
}
