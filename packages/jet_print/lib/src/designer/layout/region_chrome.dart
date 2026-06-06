/// Shared, theme-driven chrome primitives used by the designer's regions
/// (toolbox, right-panel bodies, surface). Kept in one internal file so every
/// region shares identical spacing and typography — the look that makes the
/// shell read as a single, coherent tool.
///
/// These types are library-private (under `src/`) and never exported; they are
/// `public` only so the sibling region files can reuse them.
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A compact region header: a small leading icon plus a title rendered in the
/// theme's `small` style. Used at the top of each docked region.
class RegionHeader extends StatelessWidget {
  /// Creates a region header with [icon] and [title].
  const RegionHeader({required this.icon, required this.title, super.key});

  /// The leading glyph hinting at the region's role.
  final IconData icon;

  /// The localized region caption.
  final String title;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: colors.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(color: colors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// A muted, letter-spaced section heading inside a scrollable region body.
class SectionLabel extends StatelessWidget {
  /// Creates a section label showing [text] (upper-cased for emphasis).
  const SectionLabel(this.text, {super.key});

  /// The localized section caption.
  final String text;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return Padding(
      // Flush with the panel's content edge (no left indent) so the heading
      // lines up with the property-row labels beneath it.
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.muted.copyWith(fontSize: 11, letterSpacing: 0.6),
      ),
    );
  }
}

/// Shared layout for a right-panel body: a [RegionHeader], a one-line muted
/// [hint] describing the panel's future purpose, then the panel's own
/// [children] in an independently scrollable column (FR-010). Keeps the three
/// panels (Data Source / Outline / Properties) visually consistent.
class PanelScaffold extends StatelessWidget {
  /// Creates a panel body with [icon]/[title] header, a [hint], and [children].
  const PanelScaffold({
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
    super.key,
  });

  /// The header glyph.
  final IconData icon;

  /// The localized header caption (matches the owning tab's caption).
  final String title;

  /// The localized one-line purpose hint shown under the header.
  final String hint;

  /// The panel's representative placeholder content.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RegionHeader(icon: icon, title: title),
        const ShadSeparator.horizontal(margin: EdgeInsets.zero),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(hint, style: theme.textTheme.muted),
                ),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal inset applied per tree depth, shared by the right-panel trees
/// (Data Source / Outline) so they indent identically.
const double kTreeIndentStep = 18;

/// The left inset for a tree row at [depth] (a small base plus one
/// [kTreeIndentStep] per level).
double treeRowInset(int depth) => 4 + depth * kTreeIndentStep;

/// A collapsible tree branch: a tappable header row (a disclosure chevron, the
/// node [icon], then [label]) followed by its [children] when expanded. Holds
/// its own open/closed state — the only interaction the placeholder trees
/// support. Shared by the Data Source and Outline panels so both trees expand,
/// indent, and read identically.
class TreeBranch extends StatefulWidget {
  /// Creates a branch at [depth] with [icon]/[label] over [children].
  const TreeBranch({
    required this.icon,
    required this.label,
    required this.depth,
    required this.children,
    this.initiallyExpanded = true,
    super.key,
  });

  /// The glyph hinting at the node's kind (database, table, band, …).
  final IconData icon;

  /// The node caption (illustrative sample data; not localized).
  final String label;

  /// The node's tree depth, driving its horizontal inset.
  final int depth;

  /// Whether the branch starts open.
  final bool initiallyExpanded;

  /// The rows revealed while the branch is expanded.
  final List<Widget> children;

  @override
  State<TreeBranch> createState() => _TreeBranchState();
}

class _TreeBranchState extends State<TreeBranch> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: EdgeInsets.only(
              left: treeRowInset(widget.depth),
              top: 5,
              bottom: 5,
              right: 8,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  _expanded
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  size: 14,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: 4),
                Icon(widget.icon, size: 15, color: colors.foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

/// A centered, muted hint shown when a region has no real content yet, so the
/// region never reads as a blank void (FR-007 / empty-surface edge case).
class RegionEmptyHint extends StatelessWidget {
  /// Creates an empty-state hint showing [message] under an [icon].
  const RegionEmptyHint({required this.icon, required this.message, super.key});

  /// The illustrative glyph above the message.
  final IconData icon;

  /// The localized hint text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 28, color: colors.mutedForeground),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}
