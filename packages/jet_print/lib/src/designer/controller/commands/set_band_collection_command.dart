/// The command that designates (or clears) a band's collection binding for
/// master/detail (US3 / FR-015, FR-015a).
library;

import '../../../domain/report_band.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [collectionField] of the band addressed by [path] (a list of child
/// indices from the top-level band list; `[i]` is the top-level band `i`),
/// making it a detail band that iterates that nested collection — or clears it
/// when [collectionField] is null. A no-op (no history) for an out-of-range
/// path, or when the band already has that binding.
class SetBandCollectionCommand extends EditCommand {
  /// Binds the band at [path] to [collectionField] (null clears it).
  const SetBandCollectionCommand({
    required this.path,
    required this.collectionField,
  });

  /// The path to the target band (child indices from the top-level list).
  final List<int> path;

  /// The nested-collection field the band iterates, or null to clear.
  final String? collectionField;

  @override
  String get label =>
      collectionField == null ? 'Clear band collection' : 'Bind band';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (path.isEmpty) return before;
    bool changed = false;

    ReportBand setOn(ReportBand band) {
      if (band.collectionField == collectionField) return band;
      changed = true;
      // Build directly (not copyWith) so a null [collectionField] can clear it.
      return ReportBand(
        type: band.type,
        height: band.height,
        elements: band.elements,
        group: band.group,
        collectionField: collectionField,
        children: band.children,
      );
    }

    final List<ReportBand> bands =
        _replaceAt(before.template.bands, path, setOn);
    if (!changed) return before;
    return before.withTemplate(before.template.copyWith(bands: bands));
  }
}

/// Returns a copy of [bands] with the band at [path] transformed by [update],
/// rebuilding only the touched branch (every other band preserved referentially).
List<ReportBand> _replaceAt(
  List<ReportBand> bands,
  List<int> path,
  ReportBand Function(ReportBand) update,
) {
  final int idx = path.first;
  if (idx < 0 || idx >= bands.length) return bands;
  final List<ReportBand> result = List<ReportBand>.of(bands);
  if (path.length == 1) {
    result[idx] = update(bands[idx]);
  } else {
    result[idx] = bands[idx].copyWith(
      children: _replaceAt(bands[idx].children, path.sublist(1), update),
    );
  }
  return result;
}
