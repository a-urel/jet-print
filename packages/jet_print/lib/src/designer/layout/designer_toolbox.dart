import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/jet_print_localizations.dart';

/// The left element toolbox rendered as a compact, fixed-width **icon toolbar**:
/// a vertical strip of icon-only buttons, each with a tooltip naming the report
/// element it represents — the dockable element palette of desktop report
/// designers (DevExpress / Telerik).
///
/// Layout-only this iteration: the buttons are non-functional placeholders
/// (FR-002/FR-007). Being icon-only it is already minimal, so it does not
/// collapse — it stays visible at every width. Tooltip captions come from
/// [JetPrintLocalizations]; colors from [ShadTheme]. The strip scrolls
/// internally if it ever holds more entries than fit (FR-010).
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
      _ToolboxEntry(LucideIcons.type, l10n.toolboxTextEntry),
      _ToolboxEntry(LucideIcons.table, l10n.toolboxTableEntry),
      _ToolboxEntry(LucideIcons.image, l10n.toolboxImageEntry),
      _ToolboxEntry(LucideIcons.chartColumn, l10n.toolboxChartEntry),
      _ToolboxEntry(LucideIcons.barcode, l10n.toolboxBarcodeEntry),
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
                _ToolboxButton(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

/// Immutable description of one palette entry (icon + localized tooltip).
class _ToolboxEntry {
  const _ToolboxEntry(this.icon, this.tooltip);

  final IconData icon;
  final String tooltip;
}

/// A single icon-only ghost button with a tooltip naming the element it adds.
/// Non-functional placeholder this iteration.
class _ToolboxButton extends StatelessWidget {
  const _ToolboxButton({required this.entry});

  final _ToolboxEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(entry.tooltip),
        child: ShadIconButton.ghost(
          icon: Icon(entry.icon, size: 18),
          onPressed: () {},
        ),
      ),
    );
  }
}
