import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../canvas/design_tunables.dart';
import '../controller/view_fit_mode.dart';
import '../l10n/jet_print_localizations.dart';

/// The preset zoom percentages offered in the dropdown. 100% doubles as the
/// "actual size" anchor.
const List<int> _kZoomPresets = <int>[50, 75, 100, 150, 200];

/// The editable zoom field + dropdown menu in the designer top bar.
///
/// The field always shows the live computed percentage and stays editable; the
/// active sticky fit mode (if any) is shown only by a checkmark in the menu.
/// Pure and callback-driven so it can be tested in isolation: the parent passes
/// the current [viewScale]/[fitMode] and receives intent via [onPercent] (a
/// percent value, e.g. 130) and [onFit].
class ZoomControl extends StatefulWidget {
  const ZoomControl({
    super.key,
    required this.viewScale,
    required this.fitMode,
    required this.onPercent,
    required this.onFit,
    this.keyPrefix = 'jet_print.designer',
  });

  final double viewScale;
  final JetViewFitMode fitMode;
  final ValueChanged<double> onPercent;
  final ValueChanged<JetViewFitMode> onFit;

  /// Namespace for the control's stable `ValueKey`s, so the same widget can be
  /// dropped into the designer (`jet_print.designer.*`, the default) and the
  /// preview (`jet_print.preview.*`) without key collisions.
  final String keyPrefix;

  @override
  State<ZoomControl> createState() => _ZoomControlState();
}

class _ZoomControlState extends State<ZoomControl> {
  late final TextEditingController _text =
      TextEditingController(text: _format(widget.viewScale));
  final FocusNode _focus = FocusNode();
  final ShadPopoverController _menu = ShadPopoverController();

  static String _format(double scale) => '${(scale * 100).round()}%';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ZoomControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect controller-driven scale changes, but never clobber active typing.
    if (!_focus.hasFocus && widget.viewScale != oldWidget.viewScale) {
      _text.text = _format(widget.viewScale);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final String raw = _text.text.replaceAll('%', '').trim();
    final double? parsed = double.tryParse(raw);
    if (parsed == null) {
      _text.text = _format(widget.viewScale); // reject: revert to current
      return;
    }
    // Show the value the controller will land on (it clamps identically), so a
    // later blur re-commit does not drift.
    final double clamped = (parsed / 100).clamp(kMinZoom, kMaxZoom);
    _text.text = _format(clamped);
    // Skip reporting when the rounded result is the same as what is already
    // displayed — this prevents a spurious onPercent call when the blur listener
    // fires after an invalid-entry revert (the text was reset to the current
    // scale, so parsing it again would produce the existing value).
    if (_format(clamped) == _format(widget.viewScale)) return;
    widget.onPercent(parsed);
  }

  void _pickFit(JetViewFitMode mode) {
    _menu.hide();
    widget.onFit(mode);
  }

  void _pickPreset(int percent) {
    _menu.hide();
    widget.onPercent(percent.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final int current = (widget.viewScale * 100).round();

    // The checkmark uses the established visible-when-selected pattern (the
    // glyph is always present but coloured as the background when unselected).
    Widget check(bool on) => Icon(
          LucideIcons.check,
          size: 16,
          color: on ? colors.foreground : colors.background,
        );

    return ShadTooltip(
      builder: (BuildContext context) => Text(l10n.actionZoomFieldTooltip),
      child: ShadContextMenu(
        controller: _menu,
        items: <Widget>[
          ShadContextMenuItem(
            key: ValueKey<String>('${widget.keyPrefix}.zoom.fitWidth'),
            leading: check(widget.fitMode == JetViewFitMode.width),
            onPressed: () => _pickFit(JetViewFitMode.width),
            child: Text(l10n.menuZoomFitWidth),
          ),
          ShadContextMenuItem(
            key: ValueKey<String>('${widget.keyPrefix}.zoom.fitPage'),
            leading: check(widget.fitMode == JetViewFitMode.page),
            onPressed: () => _pickFit(JetViewFitMode.page),
            child: Text(l10n.menuZoomFitPage),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: colors.border,
          ),
          for (final int p in _kZoomPresets)
            ShadContextMenuItem(
              key: ValueKey<String>('${widget.keyPrefix}.zoom.preset.$p'),
              leading:
                  check(widget.fitMode == JetViewFitMode.none && current == p),
              onPressed: () => _pickPreset(p),
              child: Text('$p%'),
            ),
        ],
        child: SizedBox(
          width: 92,
          child: ShadInput(
            key: ValueKey<String>('${widget.keyPrefix}.action.zoomLevel'),
            controller: _text,
            focusNode: _focus,
            onSubmitted: (_) => _commit(),
            trailing: GestureDetector(
              key: ValueKey<String>('${widget.keyPrefix}.zoom.menuToggle'),
              behavior: HitTestBehavior.opaque,
              onTap: _menu.toggle,
              child: const Icon(LucideIcons.chevronDown, size: 14),
            ),
          ),
        ),
      ),
    );
  }
}
