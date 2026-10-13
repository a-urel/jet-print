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

    test('copyWith replaces only the named fields, preserving the rest', () {
      const PageFormat base = PageFormat.a4Portrait;
      final PageFormat wider = base.copyWith(width: 612);
      expect(wider.width, 612);
      expect(wider.height, base.height);
      expect(wider.margins, base.margins);

      final PageFormat taller = base.copyWith(height: 1008);
      expect(taller.height, 1008);
      expect(taller.width, base.width);

      const JetEdgeInsets narrow = JetEdgeInsets.all(14.17);
      final PageFormat remargined = base.copyWith(margins: narrow);
      expect(remargined.margins, narrow);
      expect(remargined.width, base.width);
      expect(remargined.height, base.height);
    });

    test('copyWith with no arguments returns an equal value', () {
      expect(PageFormat.a4Portrait.copyWith(), PageFormat.a4Portrait);
    });

    test('a copyWith-edited page round-trips losslessly through JSON', () {
      final PageFormat edited = PageFormat.a4Portrait.copyWith(
        width: 612,
        height: 792,
        margins: const JetEdgeInsets(left: 14, top: 20, right: 14, bottom: 30),
      );
      expect(PageFormat.fromJson(edited.toJson()), edited);
    });

    group('continuous (roll paper)', () {
      test('is off by default, and an existing page serializes unchanged', () {
        expect(PageFormat.a4Portrait.continuous, isFalse);
        expect(
            PageFormat.a4Portrait.toJson().containsKey('continuous'), isFalse);
      });

      test('a continuous page writes the key and round-trips', () {
        final PageFormat roll =
            PageFormat.a4Portrait.copyWith(width: 226.77, continuous: true);
        expect(roll.toJson()['continuous'], isTrue);
        expect(PageFormat.fromJson(roll.toJson()), roll);
      });

      test('a JSON page without the key reads as not continuous', () {
        final PageFormat page = PageFormat.fromJson(<String, Object?>{
          'width': 100.0,
          'height': 200.0,
          'margins': const JetEdgeInsets.all(5).toJson(),
        });
        expect(page.continuous, isFalse);
      });

      test('takes part in equality', () {
        expect(PageFormat.a4Portrait.copyWith(continuous: true),
            isNot(PageFormat.a4Portrait));
      });

      test('copyWith preserves it unless named', () {
        final PageFormat roll =
            PageFormat.a4Portrait.copyWith(continuous: true);
        expect(roll.copyWith(height: 100).continuous, isTrue);
        expect(roll.copyWith(continuous: false).continuous, isFalse);
      });
    });
  });
}
