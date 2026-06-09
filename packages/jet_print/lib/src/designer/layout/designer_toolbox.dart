import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/geometry.dart';
import '../../domain/report_band.dart';
import '../canvas/design_tunables.dart';
import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';

/// The left element toolbox: a compact, fixed-width icon toolbar of the report
/// elements an author can add (text, shape, image, barcode — FR-002).
///
/// Each entry is both **draggable** onto the canvas (drag to place at the drop
/// point) and **clickable** (click to place into the first detail band) —
/// matching desktop report designers. Tooltip captions come from
/// [JetPrintLocalizations]; colors from [ShadTheme].
class DesignerToolbox extends StatelessWidget {
  /// Creates the toolbox. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerToolbox({super.key});

  /// Fixed width of the icon toolbar strip.
  static const double width = 52;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    final List<_ToolboxEntry> entries = <_ToolboxEntry>[
      _ToolboxEntry(
          DesignerToolType.text, LucideIcons.type, l10n.toolboxTextEntry),
      _ToolboxEntry(
          DesignerToolType.shape, LucideIcons.square, l10n.toolboxShapeEntry),
      _ToolboxEntry(
          DesignerToolType.image, LucideIcons.image, l10n.toolboxImageEntry),
      _ToolboxEntry(DesignerToolType.barcode, LucideIcons.barcode,
          l10n.toolboxBarcodeEntry),
    ];

    return SizedBox(
      width: width,
      child: ColoredBox(
        color: colors.card,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: <Widget>[
              for (final _ToolboxEntry entry in entries)
                _ToolboxButton(entry: entry, colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

/// Immutable description of one palette entry (type + icon + localized tooltip).
class _ToolboxEntry {
  const _ToolboxEntry(this.type, this.icon, this.tooltip);

  final DesignerToolType type;
  final IconData icon;
  final String tooltip;
}

/// A draggable, clickable icon button for one creatable element type.
class _ToolboxButton extends StatelessWidget {
  const _ToolboxButton({required this.entry, required this.colors});

  final _ToolboxEntry entry;
  final ShadColorScheme colors;

  /// Click-to-place: insert into the first detail band (else the first band) at
  /// a small default offset.
  void _placeByClick(BuildContext context) {
    final JetReportDesignerController controller =
        DesignerScope.of(context, listen: false);
    final List<ReportBand> bands = controller.template.bands;
    if (bands.isEmpty) return;
    int bandIndex = 0;
    for (int i = 0; i < bands.length; i++) {
      if (bands[i].type == BandType.detail) {
        bandIndex = i;
        break;
      }
    }
    controller.createElement(
      entry.type,
      bandIndex: bandIndex,
      at: const JetOffset(24, 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget button = ShadIconButton.ghost(
      key: ValueKey<String>('jet_print.designer.tool.${entry.type.name}'),
      icon: Icon(entry.icon, size: 18),
      onPressed: () => _placeByClick(context),
    );

    final Widget feedback = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(entry.icon, size: 18, color: colors.primary),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(entry.tooltip),
        child: Draggable<DesignerToolType>(
          data: entry.type,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.4, child: button),
          child: button,
        ),
      ),
    );
  }
}
