// Pure helpers lifted to top-level so the command extensions can reach
// them (a class's statics are unreachable from an extension).
part of '../jet_report_designer_controller.dart';

String? _normalizeName(String? name) =>
    (name == null || name.trim().isEmpty) ? null : name.trim();
/// A sensible default height (points) for a freshly-added band of [type].
double _defaultBandHeight(BandType type) => switch (type) {
      BandType.title || BandType.summary => 32,
      BandType.noData => 40,
      BandType.detail => 80,
      BandType.background => 200,
      _ => 24,
    };
String _typeKeyFor(DesignerToolType type) {
  switch (type) {
    case DesignerToolType.text:
      return 'text';
    case DesignerToolType.shape:
      return 'shape';
    case DesignerToolType.image:
      return 'image';
    case DesignerToolType.barcode:
      return 'barcode';
    case DesignerToolType.chart:
      return 'chart';
  }
}
