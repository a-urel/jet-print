import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/value_type.dart';

const Band _ph =
    Band(id: 'furniture/pageHeader', type: BandType.pageHeader, height: 20);
const Band _title = Band(id: 'body/title', type: BandType.title, height: 24);
const ReportBody _body = ReportBody(root: DetailScope(id: 'root'));

void main() {
  group('PageFurniture', () {
    test('slots default to null', () {
      const PageFurniture f = PageFurniture();
      expect(f.pageHeader, isNull);
      expect(f.pageFooter, isNull);
      expect(f.columnHeader, isNull);
      expect(f.columnFooter, isNull);
      expect(f.background, isNull);
    });

    test('holds page chrome and is value-equal by content', () {
      const PageFurniture a = PageFurniture(pageHeader: _ph);
      const PageFurniture b = PageFurniture(pageHeader: _ph);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const PageFurniture()));
    });

    test('copyWith replaces only the named slot', () {
      const PageFurniture f = PageFurniture(pageHeader: _ph);
      expect(f.copyWith(pageFooter: _ph).pageFooter, _ph);
      expect(f.copyWith(pageFooter: _ph).pageHeader, _ph);
    });
  });

  group('ReportBody', () {
    test('requires a root scope; title/summary/noData default to null', () {
      const ReportBody body = ReportBody(root: DetailScope(id: 'root'));
      expect(body.root.id, 'root');
      expect(body.title, isNull);
      expect(body.summary, isNull);
      expect(body.noData, isNull);
    });

    test('is value-equal by content', () {
      const ReportBody a =
          ReportBody(title: _title, root: DetailScope(id: 'root'));
      const ReportBody b =
          ReportBody(title: _title, root: DetailScope(id: 'root'));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_body));
    });

    test('copyWith replaces only named fields', () {
      expect(_body.copyWith(title: _title).title, _title);
      expect(_body.copyWith(title: _title).root.id, 'root');
    });
  });

  group('ReportDefinition', () {
    test('constructs with defaults for parameters/variables/furniture', () {
      const ReportDefinition def = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: _body,
      );
      expect(def.name, 'R');
      expect(def.page, PageFormat.a4Portrait);
      expect(def.parameters, isEmpty);
      expect(def.variables, isEmpty);
      expect(def.furniture, const PageFurniture());
      expect(def.body, _body);
    });

    test('is value-equal by content (deep over params/vars)', () {
      const ReportDefinition a = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        variables: <ReportVariable>[ReportVariable(name: 'v', expression: '1')],
        body: _body,
      );
      const ReportDefinition b = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        variables: <ReportVariable>[ReportVariable(name: 'v', expression: '1')],
        body: _body,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(
          a,
          isNot(const ReportDefinition(
              name: 'X', page: PageFormat.a4Portrait, body: _body)));
    });

    test('copyWith replaces only named fields', () {
      const ReportDefinition def = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: _body,
      );
      expect(def.copyWith(name: 'R2').name, 'R2');
      expect(def.copyWith(name: 'R2').body, _body);
      expect(
          def
              .copyWith(furniture: const PageFurniture(pageHeader: _ph))
              .furniture
              .pageHeader,
          _ph);
      expect(
          def.copyWith(parameters: const <ReportParameter>[
            ReportParameter(name: 'p', type: JetFieldType.string)
          ]).parameters,
          hasLength(1));
    });
  });
}
