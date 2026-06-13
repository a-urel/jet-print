// Style editors for the Properties panel (021 / format properties).
//
// A part of `properties_panel.dart` so the editors stay library-private and
// share the panel's vocabulary (`_p` key prefix, `_LabeledRow`, `_NumberField`,
// `_PresetDropdown`) without exposing anything. Four editors live here:
//
//  * [_ColorField]      — swatch + hex trigger opening a ShadPopover with a
//                         fixed palette, a hex input, and an optional None
//                         entry (shared by text, shape, and barcode editors);
//  * [_FontFamilyRow]   — the family picker over the designer's hoisted
//                         FontRegistry, each item previewed in its own
//                         typeface, unregistered stored names marked
//                         unavailable but preserved;
//  * [_StyleToggleGroup] — the B/I/U toggle group (Bold active ⟺ weight ==
//                         bold; intermediate weights preserved);
//  * [_AlignSegments]   — left/center/right segments (a stored justify shows
//                         no active segment and is preserved verbatim).
//
// All four follow the `_OrientationToggle` precedent: hand-rolled on shadcn
// theme tokens + lucide icons, semantic button roles, stable ValueKey seams.
part of 'properties_panel.dart';

// --- Shared color vocabulary -------------------------------------------------

/// Accepts `#RRGGBB` / `#AARRGGBB` (the `#` optional) — the only hex forms the
/// color editor commits (research §5).
final RegExp _hexColorRe = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// Formats a color for display: `#RRGGBB` when fully opaque, `#AARRGGBB`
/// otherwise — translucency stays visible without forcing 8-digit entry.
String _hexDisplay(JetColor color) {
  final String argb =
      color.argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  return argb.startsWith('FF') ? '#${argb.substring(2)}' : '#$argb';
}

/// Parses a typed hex [input]. A 6-digit value preserves [alphaSource]'s
/// stored alpha (a hue change must not discard deliberate translucency); an
/// 8-digit value sets alpha explicitly. Returns null for malformed input.
JetColor? _parseHexColor(String input, JetColor? alphaSource) {
  final RegExpMatch? match = _hexColorRe.firstMatch(input.trim());
  if (match == null) return null;
  final String digits = match.group(1)!;
  if (digits.length == 8) return JetColor(int.parse(digits, radix: 16));
  final int alpha =
      alphaSource == null ? 0xFF : (alphaSource.argb >> 24) & 0xFF;
  return JetColor((alpha << 24) | int.parse(digits, radix: 16));
}

/// One palette entry: a stable [keyName] (test seam suffix), its localized
/// accessible [label], and the opaque [color].
class _Swatch {
  const _Swatch(this.keyName, this.label, this.color);

  final String keyName;
  final String label;
  final JetColor color;
}

/// The fixed ~16-swatch palette (opaque; a pick preserves the stored alpha).
List<_Swatch> _swatches(JetPrintLocalizations l10n) => <_Swatch>[
      _Swatch('black', l10n.swatchBlack, const JetColor(0xFF000000)),
      _Swatch('white', l10n.swatchWhite, const JetColor(0xFFFFFFFF)),
      _Swatch('gray', l10n.swatchGray, const JetColor(0xFF6B7280)),
      _Swatch('silver', l10n.swatchSilver, const JetColor(0xFFD1D5DB)),
      _Swatch('red', l10n.swatchRed, const JetColor(0xFFEF4444)),
      _Swatch('orange', l10n.swatchOrange, const JetColor(0xFFF97316)),
      _Swatch('amber', l10n.swatchAmber, const JetColor(0xFFF59E0B)),
      _Swatch('yellow', l10n.swatchYellow, const JetColor(0xFFEAB308)),
      _Swatch('green', l10n.swatchGreen, const JetColor(0xFF22C55E)),
      _Swatch('emerald', l10n.swatchEmerald, const JetColor(0xFF10B981)),
      _Swatch('teal', l10n.swatchTeal, const JetColor(0xFF14B8A6)),
      _Swatch('cyan', l10n.swatchCyan, const JetColor(0xFF06B6D4)),
      _Swatch('blue', l10n.swatchBlue, const JetColor(0xFF3B82F6)),
      _Swatch('indigo', l10n.swatchIndigo, const JetColor(0xFF6366F1)),
      _Swatch('violet', l10n.swatchViolet, const JetColor(0xFF8B5CF6)),
      _Swatch('pink', l10n.swatchPink, const JetColor(0xFFEC4899)),
    ];

// --- _ColorField --------------------------------------------------------------

/// The shared color editor (C6): a trigger showing the current swatch + hex
/// (or the localized None state) that opens a popover with the palette grid, a
/// hex input, and — only where the property is optional — a None entry.
///
/// Commit rules (research §5): a swatch pick or valid 6-digit hex preserves
/// the stored alpha; a valid 8-digit hex sets alpha; malformed hex is
/// rejected — the field restores the last valid value, flashes the trigger
/// border in the destructive color, and commits nothing. Closing the popover
/// without committing discards typed input.
class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.keyBase,
    required this.value,
    required this.onCommit,
    this.allowNone = false,
  });

  /// The stable key prefix, e.g. `jet_print.designer.properties.field.fill`;
  /// the trigger gets exactly this key, sub-controls get `.swatch.*` / `.hex`
  /// / `.none` suffixes.
  final String keyBase;

  /// The current color, or null for the None state (only when [allowNone]).
  final JetColor? value;

  /// Whether the popover offers a None entry committing `null` (C7).
  final bool allowNone;

  /// Receives the committed color (null only from the None entry).
  final ValueChanged<JetColor?> onCommit;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  final ShadPopoverController _popover = ShadPopoverController();
  late final TextEditingController _hex = TextEditingController(
      text: widget.value == null ? '' : _hexDisplay(widget.value!));

  /// Invalid-input feedback: the trigger border flashes destructive briefly.
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void didUpdateWidget(_ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _hex.text = widget.value == null ? '' : _hexDisplay(widget.value!);
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _popover.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _commitHex() {
    final JetColor? parsed = _parseHexColor(_hex.text, widget.value);
    if (parsed == null) {
      // Reject: restore the last valid value and flash the trigger (C6).
      _hex.text = widget.value == null ? '' : _hexDisplay(widget.value!);
      _popover.hide();
      setState(() => _flash = true);
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _flash = false);
      });
      return;
    }
    widget.onCommit(parsed);
    _popover.hide();
  }

  void _pickSwatch(JetColor swatch) {
    // Replace RGB, preserve the stored alpha (None ⇒ fully opaque).
    final int alpha =
        widget.value == null ? 0xFF : (widget.value!.argb >> 24) & 0xFF;
    widget.onCommit(JetColor((alpha << 24) | (swatch.argb & 0x00FFFFFF)));
    _popover.hide();
  }

  void _pickNone() {
    widget.onCommit(null);
    _popover.hide();
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final JetColor? value = widget.value;

    return ShadPopover(
      controller: _popover,
      popover: (BuildContext context) => _buildPopover(theme, l10n),
      child: Semantics(
        label: l10n.colorPickerTooltip,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _popover.toggle,
          child: Container(
            key: ValueKey<String>(widget.keyBase),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(
                  color: _flash ? colors.destructive : colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: <Widget>[
                _SwatchTile(color: value, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? l10n.colorNone : _hexDisplay(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small,
                  ),
                ),
                Icon(LucideIcons.chevronDown,
                    size: 14, color: colors.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopover(ShadThemeData theme, JetPrintLocalizations l10n) {
    final ShadColorScheme colors = theme.colorScheme;
    return SizedBox(
      width: 204,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final _Swatch swatch in _swatches(l10n))
                Semantics(
                  label: swatch.label,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pickSwatch(swatch.color),
                    child: SizedBox(
                      key: ValueKey<String>(
                          '${widget.keyBase}.swatch.${swatch.keyName}'),
                      child: _SwatchTile(
                        color: swatch.color,
                        size: 20,
                        selected: widget.value != null &&
                            (widget.value!.argb & 0x00FFFFFF) ==
                                (swatch.color.argb & 0x00FFFFFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ShadInput(
            key: ValueKey<String>('${widget.keyBase}.hex'),
            controller: _hex,
            placeholder: const Text('#RRGGBB'),
            onSubmitted: (_) => _commitHex(),
          ),
          if (widget.allowNone) ...<Widget>[
            const SizedBox(height: 8),
            // No explicit Semantics label: the visible Text already names the
            // entry, and doubling it would announce "None, None".
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pickNone,
                child: Container(
                  key: ValueKey<String>('${widget.keyBase}.none'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(LucideIcons.ban,
                          size: 14, color: colors.mutedForeground),
                      const SizedBox(width: 6),
                      Text(l10n.colorNone, style: theme.textTheme.small),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small color square: the [color], or the None state (a muted ban glyph on
/// the panel background) when null. [selected] draws a check over the color so
/// the active palette entry reads at a glance.
class _SwatchTile extends StatelessWidget {
  const _SwatchTile(
      {required this.color, required this.size, this.selected = false});

  final JetColor? color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final JetColor? value = color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value == null ? colors.background : Color(value.argb),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: value == null
          ? Icon(LucideIcons.ban, size: size - 6, color: colors.mutedForeground)
          : selected
              ? Icon(LucideIcons.check,
                  size: size - 6,
                  color: _luminance(value) > 0.5
                      ? const Color(0xFF000000)
                      : const Color(0xFFFFFFFF))
              : null,
    );
  }

  /// Relative luminance of an ARGB color (0 = black, 1 = white), for picking
  /// a readable check color over a swatch.
  static double _luminance(JetColor c) {
    final int argb = c.argb;
    final double r = ((argb >> 16) & 0xFF) / 255;
    final double g = ((argb >> 8) & 0xFF) / 255;
    final double b = (argb & 0xFF) / 255;
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }
}

// --- _FontFamilyRow ------------------------------------------------------------

/// The font-family picker (C3): enumerates the designer registry's families
/// (default first), each menu item previewed in its own typeface. An element
/// whose stored family is not registered gets that name appended, selected and
/// marked unavailable (localized); the stored value survives every unrelated
/// edit until the user deliberately picks another family. Picking the default
/// family commits `fontFamily: null` — the canonical "renderer default".
class _FontFamilyRow extends StatelessWidget {
  const _FontFamilyRow({
    required this.fonts,
    required this.style,
    required this.onCommit,
  });

  final FontRegistry fonts;
  final JetTextStyle style;
  final ValueChanged<JetTextStyle> onCommit;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final List<String> families = fonts.families;
    final String? stored = style.fontFamily;
    final bool unavailable = stored != null && !families.contains(stored);
    final String effective = stored ?? FontRegistry.defaultFamily;

    return _PresetDropdown(
      fieldKey: const ValueKey<String>('$_p.field.fontFamily'),
      label: unavailable ? l10n.fontFamilyUnavailable(stored) : effective,
      tooltip: l10n.fontFamilyPickerTooltip,
      options: <_DropdownOption>[
        for (final String family in families)
          _DropdownOption(
            optionKey: ValueKey<String>('$_p.field.fontFamily.option.$family'),
            label: family,
            // Preview each family in its own typeface: the raw family name
            // first, then the canvas painter's decorated variant name (the
            // form the designer actually loads glyphs under).
            labelStyle: theme.textTheme.small.copyWith(
              fontFamily: family,
              fontFamilyFallback: <String>[
                uiFontFamily(family, JetFontWeight.normal, false),
              ],
            ),
            selected: !unavailable && effective == family,
            onPick: () => onCommit(style.copyWith(
                fontFamily:
                    family == FontRegistry.defaultFamily ? null : family)),
          ),
        if (unavailable)
          _DropdownOption(
            optionKey: ValueKey<String>('$_p.field.fontFamily.option.$stored'),
            label: l10n.fontFamilyUnavailable(stored),
            selected: true,
            // Re-picking the preserved name is a deliberate no-op: the value
            // is already stored, so the command records nothing.
            onPick: () => onCommit(style),
          ),
      ],
    );
  }
}

// --- _StyleToggleGroup ---------------------------------------------------------

/// The B/I/U toggle group (C5). Bold reads active iff the weight is exactly
/// [JetFontWeight.bold]; a press while inactive commits `bold`, while active
/// commits `normal` — intermediate weights display inactive and are preserved
/// until the toggle is operated (clarification #1). Italic and underline map
/// 1:1 to their booleans. Every press is one whole-style commit.
class _StyleToggleGroup extends StatelessWidget {
  const _StyleToggleGroup({required this.style, required this.onCommit});

  final JetTextStyle style;
  final ValueChanged<JetTextStyle> onCommit;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final bool bold = style.weight == JetFontWeight.bold;
    return _SegmentTray(
      children: <Widget>[
        _IconSegment(
          segmentKey: const ValueKey<String>('$_p.field.bold'),
          icon: LucideIcons.bold,
          label: l10n.fontBoldTooltip,
          active: bold,
          theme: theme,
          onTap: () => onCommit(style.copyWith(
              weight: bold ? JetFontWeight.normal : JetFontWeight.bold)),
        ),
        const SizedBox(width: 2),
        _IconSegment(
          segmentKey: const ValueKey<String>('$_p.field.italic'),
          icon: LucideIcons.italic,
          label: l10n.fontItalicTooltip,
          active: style.italic,
          theme: theme,
          onTap: () => onCommit(style.copyWith(italic: !style.italic)),
        ),
        const SizedBox(width: 2),
        _IconSegment(
          segmentKey: const ValueKey<String>('$_p.field.underline'),
          icon: LucideIcons.underline,
          label: l10n.fontUnderlineTooltip,
          active: style.underline,
          theme: theme,
          onTap: () => onCommit(style.copyWith(underline: !style.underline)),
        ),
      ],
    );
  }
}

// --- _AlignSegments ------------------------------------------------------------

/// The horizontal-alignment segments (left/center/right). A stored
/// [JetTextAlign.justify] shows **no** active segment and is preserved
/// verbatim by unrelated edits until the user picks an alignment (clarified
/// 2026-06-13 — justified rendering is a follow-up). Selecting the active
/// segment is a no-op, mirroring [_OrientationToggle].
class _AlignSegments extends StatelessWidget {
  const _AlignSegments({required this.align, required this.onCommit});

  final JetTextAlign align;
  final ValueChanged<JetTextAlign> onCommit;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    Widget segment(String name, IconData icon, String label, JetTextAlign value,
        {required bool expanded}) {
      final bool active = align == value;
      final Widget child = _IconSegment(
        segmentKey: ValueKey<String>('$_p.field.align.$name'),
        icon: icon,
        label: label,
        active: active,
        theme: theme,
        onTap: active ? null : () => onCommit(value),
      );
      return expanded ? Expanded(child: child) : child;
    }

    return _SegmentTray(
      children: <Widget>[
        segment('left', LucideIcons.textAlignStart, l10n.alignLeftTooltip,
            JetTextAlign.left,
            expanded: true),
        const SizedBox(width: 2),
        segment('center', LucideIcons.textAlignCenter, l10n.alignCenterTooltip,
            JetTextAlign.center,
            expanded: true),
        const SizedBox(width: 2),
        segment('right', LucideIcons.textAlignEnd, l10n.alignRightTooltip,
            JetTextAlign.right,
            expanded: true),
      ],
    );
  }
}

// --- Shared segment chrome -----------------------------------------------------

/// The iOS-style tray both segment groups sit in — the [_OrientationToggle]
/// look, shared so the Font row reads as one family of controls.
class _SegmentTray extends StatelessWidget {
  const _SegmentTray({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One icon segment in a [_SegmentTray]: a semantic button reporting its
/// [active] state, raised as a tile when active. A null [onTap] renders the
/// segment inert (the alignment groups' active segment).
class _IconSegment extends StatelessWidget {
  const _IconSegment({
    required this.segmentKey,
    required this.icon,
    required this.label,
    required this.active,
    required this.theme,
    required this.onTap,
  });

  final Key segmentKey;
  final IconData icon;
  final String label;
  final bool active;
  final ShadThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: segmentKey,
          width: 30,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? colors.background : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 14,
            color: active ? colors.foreground : colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
