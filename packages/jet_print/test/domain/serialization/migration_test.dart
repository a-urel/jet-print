import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/serialization/migration.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';

/// Renames a top-level `title` key to `name` (a representative v0 -> v1 change).
class _RenameTitleToName extends SchemaMigration {
  @override
  int get fromVersion => 0;

  @override
  Map<String, Object?> upgrade(Map<String, Object?> json) {
    final Map<String, Object?> next = Map<String, Object?>.of(json)
      ..['name'] = json['title']
      ..remove('title');
    return next;
  }
}

void main() {
  group('runMigrations', () {
    test('returns the input unchanged when already current', () {
      final Map<String, Object?> json = <String, Object?>{'name': 'X'};
      expect(
        runMigrations(json,
            from: 1, to: 1, migrations: const <SchemaMigration>[]),
        same(json),
      );
    });

    test('applies ordered migrations from old version to current', () {
      final Map<String, Object?> upgraded = runMigrations(
        <String, Object?>{'title': 'Old'},
        from: 0,
        to: 1,
        migrations: <SchemaMigration>[_RenameTitleToName()],
      );
      expect(upgraded['name'], 'Old');
      expect(upgraded.containsKey('title'), isFalse);
    });

    test('throws when a version step has no migration', () {
      expect(
        () => runMigrations(
          <String, Object?>{},
          from: 0,
          to: 1,
          migrations: const <SchemaMigration>[],
        ),
        throwsA(isA<ReportFormatException>()),
      );
    });
  });
}
