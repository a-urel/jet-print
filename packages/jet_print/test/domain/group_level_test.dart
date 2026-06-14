import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

void main() {
  group('GroupLevel', () {
    test('constructs with id, name, key, optional bands and flags', () {
      const GroupLevel g = GroupLevel(
        id: 'g1',
        name: 'invoice',
        key: r'$F{invoiceNo}',
        header: Band(id: 'g1/header', type: BandType.groupHeader, height: 40),
        footer: Band(id: 'g1/footer', type: BandType.groupFooter, height: 20),
        keepTogether: true,
        startNewPage: true,
      );
      expect(g.id, 'g1');
      expect(g.name, 'invoice');
      expect(g.key, r'$F{invoiceNo}');
      expect(g.header?.type, BandType.groupHeader);
      expect(g.footer?.type, BandType.groupFooter);
      expect(g.keepTogether, isTrue);
      expect(g.reprintHeaderOnEachPage, isFalse);
      expect(g.startNewPage, isTrue);
    });

    test('flags default to false; bands default to null', () {
      const GroupLevel g = GroupLevel(id: 'g', name: 'n', key: '1');
      expect(g.header, isNull);
      expect(g.footer, isNull);
      expect(g.keepTogether, isFalse);
      expect(g.reprintHeaderOnEachPage, isFalse);
      expect(g.startNewPage, isFalse);
    });

    test('is value-equal by content', () {
      const GroupLevel a = GroupLevel(id: 'g', name: 'n', key: '1');
      const GroupLevel b = GroupLevel(id: 'g', name: 'n', key: '1');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const GroupLevel(id: 'g', name: 'n', key: '2')));
      expect(
          a,
          isNot(const GroupLevel(
              id: 'g', name: 'n', key: '1', startNewPage: true)));
    });

    test('copyWith replaces only named fields', () {
      const GroupLevel g = GroupLevel(id: 'g', name: 'n', key: '1');
      expect(g.copyWith(startNewPage: true).startNewPage, isTrue);
      expect(g.copyWith(name: 'x').name, 'x');
      expect(g.copyWith(name: 'x').key, '1');
    });
  });
}
