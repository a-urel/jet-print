import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../../../domain/report_template.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../controller/selection.dart';
import '../../designer_scope.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../region_chrome.dart';

/// Subtle accent tint marking the row whose object is currently selected; matches
/// the canvas selection accent at a low alpha so the highlight reads on white.
const Color _selectedRowColor = Color(0x142563EB);

/// Body of the **Outline** tab: the live report as an indented, collapsible tree
/// — a Report root, one branch per band (its localized band-type caption and
/// glyph), and a leaf per element (its toolbox glyph and id) (FR-007). The tree
/// is driven entirely by the controller's `template`/`selection`:
///
/// * the row whose object is selected is highlighted (and marked selected for
///   accessibility);
/// * tapping a row selects that object — the report, a band, or an element —
///   through the controller, which the canvas and Properties panel observe;
/// * the disclosure chevron collapses/expands a branch (independent of select).
///
/// Expansion is view state held here (not in the model); it resets when the tab
/// is re-opened, with everything expanded.
class OutlinePanel extends StatefulWidget {
  /// Creates the Outline panel body. Private to the library.
  const OutlinePanel({super.key});

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  bool _rootExpanded = true;

  /// Indices of bands the user has collapsed (absent ⇒ expanded).
  final Set<int> _collapsedBands = <int>{};

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ReportTemplate template = controller.template;
    final Selection selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    final List<Widget> rows = <Widget>[
      _branchRow(
        rowKey: const ValueKey<String>('jet_print.designer.outline.report'),
        toggleKey:
            const ValueKey<String>('jet_print.designer.outline.report.toggle'),
        depth: 0,
        icon: LucideIcons.fileText,
        label: 'Report',
        expanded: _rootExpanded,
        selected: selection.isReport,
        onToggle: () => setState(() => _rootExpanded = !_rootExpanded),
        onSelect: controller.selectReport,
        theme: theme,
      ),
    ];

    if (_rootExpanded) {
      for (int i = 0; i < template.bands.length; i++) {
        final ReportBand band = template.bands[i];
        final bool expanded = !_collapsedBands.contains(i);
        rows.add(_branchRow(
          rowKey: ValueKey<String>('jet_print.designer.outline.band.$i'),
          toggleKey:
              ValueKey<String>('jet_print.designer.outline.band.$i.toggle'),
          depth: 1,
          icon: _bandGlyph(band.type),
          label: bandTypeLabel(band.type, l10n),
          expanded: expanded,
          selected: selection.bandIndex == i,
          onToggle: () => setState(() {
            // Set.add returns false when already collapsed → expand instead.
            if (!_collapsedBands.add(i)) _collapsedBands.remove(i);
          }),
          onSelect: () => controller.selectBand(i),
          theme: theme,
        ));
        if (expanded) {
          for (final ReportElement element in band.elements) {
            rows.add(_leafRow(
              rowKey: ValueKey<String>(
                  'jet_print.designer.outline.element.${element.id}'),
              icon: _elementGlyph(element),
              label: element.id,
              selected: selection.contains(element.id),
              onSelect: () => controller.select(element.id),
              theme: theme,
            ));
          }
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  /// An expandable branch row (the report root or a band): a disclosure chevron
  /// that toggles, then the node glyph and label; tapping the row (not the
  /// chevron) selects the node.
  Widget _branchRow({
    required Key rowKey,
    required Key toggleKey,
    required int depth,
    required IconData icon,
    required String label,
    required bool expanded,
    required bool selected,
    required VoidCallback onToggle,
    required VoidCallback onSelect,
    required ShadThemeData theme,
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    return KeyedSubtree(
      key: rowKey,
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: ColoredBox(
              color: selected ? _selectedRowColor : const Color(0x00000000),
              child: Padding(
                padding: EdgeInsets.only(
                    left: treeRowInset(depth), top: 4, bottom: 4, right: 8),
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      key: toggleKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: Icon(
                        expanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight,
                        size: 14,
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(icon, size: 14, color: colors.mutedForeground),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A leaf element row: the element glyph then its id; tapping it selects the
  /// element. Indented past the chevron column so it aligns under branch labels.
  Widget _leafRow({
    required Key rowKey,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onSelect,
    required ShadThemeData theme,
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    return KeyedSubtree(
      key: rowKey,
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: ColoredBox(
              color: selected ? _selectedRowColor : const Color(0x00000000),
              child: Padding(
                // +18 ≈ chevron width + gap, aligning the glyph under branches'.
                padding: EdgeInsets.only(
                    left: treeRowInset(2) + 18, top: 4, bottom: 4, right: 8),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 14, color: colors.mutedForeground),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The tree glyph for a band: header-like bands get a top-panel glyph,
  /// footer-like bands a bottom-panel glyph, detail/no-data a rows glyph.
  IconData _bandGlyph(BandType type) {
    switch (type) {
      case BandType.title:
      case BandType.pageHeader:
      case BandType.columnHeader:
      case BandType.groupHeader:
        return LucideIcons.panelTop;
      case BandType.groupFooter:
      case BandType.columnFooter:
      case BandType.pageFooter:
      case BandType.summary:
        return LucideIcons.panelBottom;
      case BandType.detail:
      case BandType.noData:
        return LucideIcons.rows3;
      case BandType.background:
        return LucideIcons.image;
    }
  }

  /// The toolbox glyph for an element, so an outline leaf and the palette element
  /// it came from read as the same thing.
  IconData _elementGlyph(ReportElement element) {
    if (element is TextElement) return LucideIcons.type;
    if (element is ShapeElement) return LucideIcons.square;
    if (element is ImageElement) return LucideIcons.image;
    if (element is BarcodeElement) return LucideIcons.barcode;
    return LucideIcons.square;
  }
}
