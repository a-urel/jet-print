import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../region_chrome.dart';

/// Body of the **Outline** tab: an expandable hierarchical tree of the report's
/// bands and elements, shaped like the document outline of a real report
/// designer so its role is self-evident (FR-007). Like the Data Source tab it
/// has no header/title or hint text — the tree is the panel, and the owning tab
/// already names it — and it shares that tab's collapsible row shape via the
/// common [TreeBranch], so the two trees expand, indent, and read as one tool.
///
/// Bands (Report, Page Header, …) are branches that collapse to hide their
/// contents; element rows are leaves that reuse the toolbox glyphs (a text
/// element shows the Text glyph, a table element the Table glyph) so an outline
/// entry and the palette element it came from look like the same thing. The
/// node names are illustrative sample data (not localized).
class OutlinePanel extends StatelessWidget {
  /// Creates the Outline panel body. Private to the library.
  const OutlinePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TreeBranch(
            icon: LucideIcons.fileText,
            label: 'Report',
            depth: 0,
            children: <Widget>[
              TreeBranch(
                icon: LucideIcons.panelTop,
                label: 'Page Header',
                depth: 1,
                children: const <Widget>[
                  // Text element → the toolbox Text glyph.
                  _ElementRow(icon: LucideIcons.type, label: 'Title', depth: 2),
                ],
              ),
              TreeBranch(
                icon: LucideIcons.rows3,
                label: 'Detail',
                depth: 1,
                children: const <Widget>[
                  // Table element → the toolbox Table glyph.
                  _ElementRow(
                    icon: LucideIcons.table,
                    label: 'OrdersTable',
                    depth: 2,
                  ),
                ],
              ),
              TreeBranch(
                icon: LucideIcons.panelBottom,
                label: 'Page Footer',
                depth: 1,
                children: const <Widget>[
                  // Page-number field.
                  _ElementRow(
                    icon: LucideIcons.hash,
                    label: 'PageInfo',
                    depth: 2,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A leaf element row: the element glyph then its name. Band (branch) rows come
/// from the shared [TreeBranch].
class _ElementRow extends StatelessWidget {
  const _ElementRow({
    required this.icon,
    required this.label,
    required this.depth,
  });

  final IconData icon;
  final String label;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: treeRowInset(depth),
        top: 4,
        bottom: 4,
        right: 8,
      ),
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
    );
  }
}
