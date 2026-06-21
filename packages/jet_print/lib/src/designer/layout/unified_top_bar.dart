/// The shared toolbar **shell** behind both the designer's top bar and the
/// report preview's toolbar (017). Extracting it is what makes the designer and
/// the preview read as *one toolbar that changes by context*: the left
/// (file icon + report name) and center (the Designer|Preview mode switch)
/// regions are produced by this single widget, so they occupy the **same
/// position and visual style** in both modes (FR-001, SC-003) — only the
/// right-hand [actions] slot differs (FR-011).
///
/// The report name is shown read-only here; renaming is surfaced elsewhere by
/// the host (the controller's `rename` mutator / the preview's `onRename`).
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/jet_print_localizations.dart';

/// Below this screen width — a phone or a very narrow window — the shared
/// toolbar collapses its space-hungry, non-essential controls to their
/// glyph-only essentials: the mode switch drops its segment labels and the
/// designer hides its editable zoom field (the +/− buttons stay). The top bar
/// spans the workspace width, so a screen-width read matches the bar's width.
/// Desktop/tablet keep the full controls, so their rendering — and the
/// goldens — is unchanged.
const double kBarVeryNarrowWidth = 600;

/// Builds the mode-specific right-slot actions. [compact] is true at narrow
/// widths, signalling labelled actions to collapse to icon-only (the designer
/// uses it; the preview, already icon-only, ignores it). [veryNarrow] is true
/// only on a phone / very narrow bar ([kBarVeryNarrowWidth]); the designer uses
/// it to drop the editable zoom field entirely.
typedef UnifiedActionsBuilder = List<Widget> Function(
    BuildContext context, bool compact, bool veryNarrow);

/// Builds the bar's center region (the Designer|Preview mode switch).
/// [veryNarrow] is true on a phone / very narrow bar ([kBarVeryNarrowWidth]),
/// signalling the switch to drop its segment labels and go icon-only.
typedef UnifiedCenterBuilder = Widget Function(
    BuildContext context, bool veryNarrow);

/// The shared three-region command-bar shell composed by [DesignerTopBar] and
/// [JetReportPreview].
///
/// Layout (left → right): a [leadingIcon] + the report [name] (ellipsized,
/// placeholder when empty), the [center] mode switch, then the caller's
/// [actions], right-aligned. The left + center regions are identical across
/// modes by construction (one widget renders them), so the mode switch sits at
/// the same position whether the bar is hosting the designer or the preview
/// (INV-1). Nothing can overflow: the actions live in a horizontally
/// scrollable, right-pinned area, with an outer scroll as the extreme-narrow
/// safety net.
class UnifiedTopBar extends StatelessWidget {
  /// Creates the shell. [leadingIcon] titles the bar; [name] is the current
  /// stored report name (empty/whitespace renders the localized placeholder);
  /// [center] is the mode switch; [actions] fills the right slot per mode.
  const UnifiedTopBar({
    super.key,
    required this.leadingIcon,
    required this.name,
    required this.centerBuilder,
    required this.actions,
    this.compactWidth = 920,
    this.scrollWidth = 700,
  });

  /// The leading glyph (a file icon in the designer, an eye in the preview).
  final IconData leadingIcon;

  /// The current stored report name. Empty or whitespace-only renders the
  /// localized placeholder (`reportTitlePlaceholder`), identically in both
  /// modes (FR-006, FR-010).
  final String name;

  /// Builds the center region — the Designer|Preview mode switch — given the
  /// bar's [veryNarrow] state so the switch can go icon-only on a phone.
  final UnifiedCenterBuilder centerBuilder;

  /// Builds the mode-specific right-slot actions (FR-011).
  final UnifiedActionsBuilder actions;

  /// Below this width the [actions] are asked to render compact (icon-only).
  final double compactWidth;

  /// At or above this width the actions are pinned to the right edge (a flexible
  /// gap separates them from the switch). Below it the whole bar scrolls
  /// horizontally instead of overflowing — the leading name + switch stay at the
  /// start, so they remain visible at scroll origin while the trailing actions
  /// scroll into view (C6.1 / C6.2).
  final double scrollWidth;

  /// The shared bar height — identical in both modes (FR-001 / C1.3).
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;

    return ColoredBox(
      color: colors.card,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final bool compact = width < compactWidth;
              final bool scrollable = width < scrollWidth;
              // A phone / very narrow bar: the mode switch goes icon-only and
              // the designer hides its editable zoom field (shared bar line).
              final bool veryNarrow = width < kBarVeryNarrowWidth;
              final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
              final List<Widget> leadPrefix = <Widget>[
                const SizedBox(width: 4),
                Icon(leadingIcon, size: 18, color: colors.mutedForeground),
                const SizedBox(width: 10),
              ];
              final Widget nameRegion = _NameRegion(name: name);

              if (scrollable) {
                // Narrow: everything keeps its natural width and scrolls, so
                // nothing overflows. The name + switch lead, so they are visible
                // at the scroll origin while the trailing actions scroll in
                // (C6.2). The name is its natural (bounded) width here.
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    height: height,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ...leadPrefix,
                        nameRegion,
                        const SizedBox(width: 8),
                        centerBuilder(context, veryNarrow),
                        const SizedBox(width: 8),
                        ...actions(context, compact, veryNarrow),
                      ],
                    ),
                  ),
                );
              }
              // Wide: the name is the flexible child — it ellipsizes to give the
              // switch and actions their room, so the bar never overflows above
              // the scroll threshold. The switch stays positioned from the
              // leading edge (after the name), so for a given name it lands at
              // the same place in both modes (INV-1 / parity).
              return Row(
                children: <Widget>[
                  ...leadPrefix,
                  Flexible(child: nameRegion),
                  const SizedBox(width: 8),
                  centerBuilder(context, veryNarrow),
                  const SizedBox(width: 8),
                  ...actions(context, compact, veryNarrow),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The report-name region: the stored name shown read-only, with the localized
/// placeholder when it is empty/whitespace (FR-006, FR-010).
///
/// Renaming is no longer surfaced from the toolbar; the host drives it elsewhere
/// through the controller's `rename` mutator (or the preview's `onRename`).
class _NameRegion extends StatelessWidget {
  const _NameRegion({required this.name});

  final String name;

  /// The name region's maximum width: a long name ellipsizes here instead of
  /// pushing the mode switch or the actions off-screen (spec Edge Cases).
  static const double maxWidth = 240;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    final String shown =
        name.trim().isEmpty ? l10n.reportTitlePlaceholder : name;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Text(
        shown,
        key: const ValueKey<String>('jet_print.toolbar.name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.large.copyWith(color: colors.foreground),
      ),
    );
  }
}
