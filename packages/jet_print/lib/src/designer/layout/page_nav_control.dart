import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/jet_print_localizations.dart';
import 'popover_group.dart';

/// The report preview's page-position indicator, made interactive: the
/// "Page X of Y" label is a dropdown trigger offering quick page jumps — First
/// page, Last page, and a "Go to page" number field.
///
/// Pure and callback-driven so it can be tested in isolation: the parent passes
/// the current zero-based [pageIndex] and [pageCount] and receives the requested
/// destination index via [onGoTo] (also zero-based). It never holds page state.
class PageNavControl extends StatefulWidget {
  const PageNavControl({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    required this.onGoTo,
    this.keyPrefix = 'jet_print.preview',
    this.popoverGroup,
  });

  /// The current page, zero-based.
  final int pageIndex;

  /// The total number of pages (at least 1).
  final int pageCount;

  /// Invoked with the requested destination page, zero-based and already clamped
  /// into `[0, pageCount - 1]`.
  final ValueChanged<int> onGoTo;

  /// Namespace for the control's stable `ValueKey`s, mirroring [ZoomControl] so
  /// the same widget can live in the designer (`jet_print.designer.*`) or the
  /// preview (`jet_print.preview.*`, the default) without key collisions.
  final String keyPrefix;

  /// Optional shared group that closes this popup when a sibling popup (e.g. the
  /// zoom dropdown) opens, so at most one toolbar popover is open at a time.
  final PopoverGroup? popoverGroup;

  @override
  State<PageNavControl> createState() => _PageNavControlState();
}

class _PageNavControlState extends State<PageNavControl> {
  final ShadPopoverController _menu = ShadPopoverController();
  final TextEditingController _goto = TextEditingController();
  final FocusNode _gotoFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.popoverGroup?.add(_menu);
  }

  @override
  void didUpdateWidget(PageNavControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.popoverGroup, widget.popoverGroup)) {
      oldWidget.popoverGroup?.remove(_menu);
      widget.popoverGroup?.add(_menu);
    }
  }

  @override
  void dispose() {
    widget.popoverGroup?.remove(_menu);
    _menu.dispose();
    _goto.dispose();
    _gotoFocus.dispose();
    super.dispose();
  }

  void _go(int index) {
    _menu.hide();
    widget.onGoTo(index);
  }

  void _submitGoto() {
    final int? parsed = int.tryParse(_goto.text.trim());
    if (parsed == null) {
      _goto.clear();
      return; // reject: a non-numeric entry reports nothing
    }
    // The field is 1-based; clamp into the valid 1-based range, then convert.
    final int oneBased = parsed.clamp(1, widget.pageCount);
    _goto.clear();
    _go(oneBased - 1);
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;

    final bool atFirst = widget.pageIndex <= 0;
    final bool atLast = widget.pageIndex >= widget.pageCount - 1;

    return ShadContextMenu(
      controller: _menu,
      items: <Widget>[
        ShadContextMenuItem(
          key: ValueKey<String>('${widget.keyPrefix}.page.first'),
          enabled: !atFirst,
          onPressed: atFirst ? null : () => _go(0),
          child: Text(l10n.previewFirstPage),
        ),
        ShadContextMenuItem(
          key: ValueKey<String>('${widget.keyPrefix}.page.last'),
          enabled: !atLast,
          onPressed: atLast ? null : () => _go(widget.pageCount - 1),
          child: Text(l10n.previewLastPage),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: colors.border,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SizedBox(
            width: 140,
            child: ShadInput(
              key: ValueKey<String>('${widget.keyPrefix}.page.gotoField'),
              controller: _goto,
              focusNode: _gotoFocus,
              placeholder: Text(l10n.previewGoToPage),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onSubmitted: (_) => _submitGoto(),
            ),
          ),
        ),
      ],
      child: GestureDetector(
        key: ValueKey<String>('${widget.keyPrefix}.page.menuToggle'),
        behavior: HitTestBehavior.opaque,
        onTap: _menu.toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.previewPageIndicator(
                    widget.pageIndex + 1, widget.pageCount),
                style: theme.textTheme.small.copyWith(color: colors.foreground),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown,
                  size: 14, color: colors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
