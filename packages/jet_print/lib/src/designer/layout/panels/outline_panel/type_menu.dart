// The outline's add/retype menu widgets (_MenuOption, _TypeMenu).
part of '../outline_panel.dart';

/// One option in a [_TypeMenu]. A leaf option carries an [onPick]; a submenu
/// parent carries [children] (and no [onPick]). [enabled] greys a parent out
/// (e.g. "Add group" when no scalar field is in scope).
class _MenuOption {
  const _MenuOption({
    required this.optionKey,
    required this.label,
    this.onPick,
    this.children = const <_MenuOption>[],
    this.enabled = true,
  });

  final Key optionKey;
  final String label;
  final VoidCallback? onPick;
  final List<_MenuOption> children;
  final bool enabled;
}

/// A compact popup that picks a target band type/slot: the trigger is a keyed
/// glyph; tapping it drops a menu of [options]. Inert (no menu) when [options]
/// is empty — e.g. a band that has no free slot to retype into.
class _TypeMenu extends StatefulWidget {
  const _TypeMenu({
    required this.triggerKey,
    required this.icon,
    required this.tooltip,
    required this.options,
    required this.colors,
  });

  final Key triggerKey;
  final IconData icon;
  final String tooltip;
  final List<_MenuOption> options;
  final ShadColorScheme colors;

  @override
  State<_TypeMenu> createState() => _TypeMenuState();
}

class _TypeMenuState extends State<_TypeMenu> {
  final ShadPopoverController _menu = ShadPopoverController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  Widget _item(_MenuOption opt) => ShadContextMenuItem(
        key: opt.optionKey,
        enabled: opt.enabled,
        // shadcn's default submenu anchor stacks the child panel over the
        // parent (its right edge pins to the parent's right edge), so the
        // nested options read as a flat list. Open it BESIDE the parent
        // instead: the child's left edge meets the parent's right edge. No
        // horizontal flip ships upstream, so a near-bottom trigger gets a
        // vertical fallback only. Leaf items keep the default (null).
        anchor: opt.children.isEmpty
            ? null
            : const ShadAnchorAuto(
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.topLeft,
                offset: Offset(4, -8),
                fallback: ShadAnchorAuto(
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.bottomLeft,
                  offset: Offset(4, 8),
                ),
              ),
        onPressed: opt.children.isEmpty
            ? () {
                _menu.hide();
                opt.onPick?.call();
              }
            : null,
        items: <Widget>[for (final _MenuOption c in opt.children) _item(c)],
        child: Text(opt.label),
      );

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.options.isNotEmpty;
    return ShadContextMenu(
      controller: _menu,
      items: <Widget>[
        for (final _MenuOption opt in widget.options) _item(opt),
      ],
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.tooltip,
          child: GestureDetector(
            key: widget.triggerKey,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _menu.toggle : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                widget.icon,
                size: 13,
                color: enabled
                    ? widget.colors.mutedForeground
                    : widget.colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
