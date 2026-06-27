import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// One entry in the playground's demo navigation: the stable [value] that keys
/// the selected demo, the [icon] shown beside it, and the localized [label].
@immutable
class DemoNavItem {
  const DemoNavItem({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

/// A vertical, scrollable list of selectable demo entries, shared by the wide
/// layout's fixed sidebar and the narrow layout's hamburger drawer.
///
/// Stateless: the parent owns [selected] and is notified through [onSelect].
/// The widget carries no chrome (border/width) — that is the caller's job — so
/// the identical list renders in either host.
class DemoNavList extends StatelessWidget {
  const DemoNavList({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<DemoNavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final DemoNavItem item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: _tile(item),
            ),
        ],
      ),
    );
  }

  // A selected entry uses the filled `secondary` variant for an accent
  // background; the rest are borderless `ghost`. Both are full-width and
  // left-aligned (`mainAxisAlignment: start`) so the icon+label read as a list
  // row, not a centered button.
  Widget _tile(DemoNavItem item) {
    final bool isSelected = item.value == selected;
    final Widget leading = Icon(item.icon, size: 16);
    // `expands: true` lets the label fill the button's width; textAlign.left
    // then keeps it flush against the leading icon (the default centers it).
    final Widget label = Text(item.label, textAlign: TextAlign.left);
    void onPressed() => onSelect(item.value);
    return isSelected
        ? ShadButton.secondary(
            width: double.infinity,
            mainAxisAlignment: MainAxisAlignment.start,
            expands: true,
            leading: leading,
            onPressed: onPressed,
            child: label,
          )
        : ShadButton.ghost(
            width: double.infinity,
            mainAxisAlignment: MainAxisAlignment.start,
            expands: true,
            leading: leading,
            onPressed: onPressed,
            child: label,
          );
  }
}
