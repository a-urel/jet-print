/// The command that changes selected elements' z-order within their band (FR-013).
library;

import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// How a [ReorderCommand] moves the selected elements within `band.elements`
/// (paint order: later index = drawn on top).
enum ReorderMode {
  /// Move each selected element one step toward the front (later index).
  forward,

  /// Move each selected element one step toward the back (earlier index).
  backward,

  /// Move all selected elements to the front (end of the list).
  toFront,

  /// Move all selected elements to the back (start of the list).
  toBack,
}

/// Reorders the elements named in [ids] within each band that contains them,
/// per [mode]. The relative order of the selected elements is preserved.
class ReorderCommand extends EditCommand {
  /// Creates a reorder of [ids] using [mode].
  const ReorderCommand(this.ids, this.mode);

  /// The element ids to reorder.
  final Set<String> ids;

  /// The reorder direction.
  final ReorderMode mode;

  @override
  String get label => 'Reorder';

  @override
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) => ids.contains(e.id)))
          () {
            final List<ReportElement> reordered = _reorder(band.elements);
            changed = true;
            return band.copyWith(elements: reordered);
          }()
        else
          band,
    ];
    if (!changed) return before;
    return before.withTemplate(before.template.copyWith(bands: bands));
  }

  List<ReportElement> _reorder(List<ReportElement> elements) {
    final List<ReportElement> selected = <ReportElement>[
      for (final ReportElement e in elements) if (ids.contains(e.id)) e,
    ];
    final List<ReportElement> others = <ReportElement>[
      for (final ReportElement e in elements) if (!ids.contains(e.id)) e,
    ];
    switch (mode) {
      case ReorderMode.toFront:
        return <ReportElement>[...others, ...selected];
      case ReorderMode.toBack:
        return <ReportElement>[...selected, ...others];
      case ReorderMode.forward:
        return _shift(elements, toward: 1);
      case ReorderMode.backward:
        return _shift(elements, toward: -1);
    }
  }

  /// Shifts each selected element one slot in [toward] (+1 front, -1 back),
  /// processing in the order that avoids selected elements leapfrogging.
  List<ReportElement> _shift(List<ReportElement> elements, {required int toward}) {
    final List<ReportElement> out = List<ReportElement>.of(elements);
    final Iterable<int> order = toward > 0
        ? Iterable<int>.generate(out.length, (int i) => out.length - 1 - i)
        : Iterable<int>.generate(out.length, (int i) => i);
    for (final int i in order) {
      if (!ids.contains(out[i].id)) continue;
      final int j = i + toward;
      if (j < 0 || j >= out.length || ids.contains(out[j].id)) continue;
      final ReportElement tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }
}
