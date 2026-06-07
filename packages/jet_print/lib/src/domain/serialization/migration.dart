/// Forward migration of older report JSON to the current schema (Constitution V).
library;

import 'report_format_exception.dart';

/// Upgrades a report JSON map from [fromVersion] to [fromVersion] + 1.
///
/// Implementations are pure map-to-map transforms; chain them with
/// [runMigrations]. Each schema bump ships exactly one migration for the
/// previous version so any older file can be walked forward to current.
abstract class SchemaMigration {
  /// The schema version this migration upgrades **from**.
  int get fromVersion;

  /// Returns a new map upgraded to `fromVersion + 1`. Must not mutate [json].
  Map<String, Object?> upgrade(Map<String, Object?> json);
}

/// Walks [json] forward from version [from] to version [to] by applying the
/// matching [migrations] one version at a time. Returns [json] unchanged when
/// `from == to`. Throws [ReportFormatException] if a step has no migration.
Map<String, Object?> runMigrations(
  Map<String, Object?> json, {
  required int from,
  required int to,
  required List<SchemaMigration> migrations,
}) {
  Map<String, Object?> current = json;
  int version = from;
  while (version < to) {
    final int step = version;
    final SchemaMigration migration = migrations.firstWhere(
      (SchemaMigration m) => m.fromVersion == step,
      orElse: () => throw ReportFormatException(
        'No migration registered from schemaVersion $step.',
      ),
    );
    current = migration.upgrade(current);
    version += 1;
  }
  return current;
}
