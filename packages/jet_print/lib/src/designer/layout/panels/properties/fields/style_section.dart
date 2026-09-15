// Composed style editors for the Properties panel (spec C).
//
// A part of `properties_panel.dart`, like every other panel file, so these
// compose the library-private editors in `style_editors.dart` without exposing
// anything.
//
// These exist because eight crosstab appearance slots need the same controls
// the element inspector had assembled inline: composing them per slot would
// have meant repeating ~75 lines eight times, which is why spec B deferred the
// crosstab style editors in the first place.
//
// Key composition is load-bearing. Keys are built as `'$keyBase.<name>'`, and
// the element inspector passes `keyBase: '$_p.field'` so the shipped keys
// (`$_p.field.fontSize`, `$_p.field.textColor`, …) survive verbatim — 85 tests
// in properties_editor_test.dart find widgets through exactly those strings.
part of '../../properties_panel.dart';

/// A composed [JetTextStyle] editor: family, size and colour on one row;
/// the B/I/U toggles and alignment segments on the next.
///
/// Every control commits one whole style through [onCommit], so each change is
/// a single undoable step. The widget is stateless and holds no draft:
/// callers wrap it in a `KeyedSubtree` keyed by the edited object's id when a
/// selection switch should discard uncommitted input.
class _TextStyleEditor extends StatelessWidget {
  const _TextStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
  });

  /// Prefix for every child key; children append `.fontSize`, `.textColor`.
  final String keyBase;

  /// The style the editors display — for a nullable slot, the effective value
  /// it would inherit, so the controls are never blank.
  final JetTextStyle style;

  /// Receives the whole updated style on every committed change.
  final ValueChanged<JetTextStyle> onCommit;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Family, size and color share one compact row — no left labels.
        // The family picker takes the slack; size is a fixed-width field
        // (its leading glyph stands in for the dropped "Size" label); the
        // color trigger is a square swatch-only box.
        Row(
          children: <Widget>[
            Expanded(
              child: _FontFamilyRow(
                fonts: DesignerFontScope.of(context),
                showBuiltIns: DesignerFontScope.showBuiltInsOf(context),
                style: style,
                onCommit: onCommit,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 84,
              child: _PresetDropdown(
                fieldKey: ValueKey<String>('$keyBase.fontSize'),
                label: _format(style.fontSize),
                tooltip: l10n.fontSizeLabel,
                options: <_DropdownOption>[
                  for (final double size in _fontSizePresets)
                    _DropdownOption(
                      optionKey: ValueKey<String>(
                          '$keyBase.fontSize.option.${_format(size)}'),
                      label: _format(size),
                      selected: style.fontSize == size,
                      onPick: () => onCommit(style.copyWith(fontSize: size)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _ColorField(
              keyBase: '$keyBase.textColor',
              value: style.color,
              compact: true,
              onCommit: (JetColor? c) => onCommit(style.copyWith(color: c)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            _StyleToggleGroup(
                keyBase: keyBase, style: style, onCommit: onCommit),
            const SizedBox(width: 8),
            Expanded(
              child: _AlignSegments(
                keyBase: keyBase,
                align: style.align,
                onCommit: (JetTextAlign a) =>
                    onCommit(style.copyWith(align: a)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A composed [JetBoxStyle] editor: fill and outline swatches plus an outline
/// width preset, all on one label-less row.
///
/// [showFill] is false where the shape has no interior — the line shape drops
/// its fill box, a shipped behaviour this flag exists to preserve. No crosstab
/// slot uses it, so it would regress silently without a test.
class _BoxStyleEditor extends StatelessWidget {
  const _BoxStyleEditor({
    required this.keyBase,
    required this.style,
    required this.onCommit,
    this.showFill = true,
  });

  /// Prefix for every child key; children append `.fill`, `.stroke`,
  /// `.strokeWidth`.
  final String keyBase;

  /// The box style the editors display.
  final JetBoxStyle style;

  /// Receives the whole updated style on every committed change.
  final ValueChanged<JetBoxStyle> onCommit;

  /// Whether to show the fill swatch.
  final bool showFill;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    // Fill, outline and width share one label-less row. The two color boxes
    // are compact swatches distinguished by a leading glyph (bucket = fill,
    // square = outline). Width fills the remaining width.
    return Row(
      children: <Widget>[
        if (showFill) ...<Widget>[
          _ColorField(
            keyBase: '$keyBase.fill',
            value: style.fill,
            allowNone: true,
            compact: true,
            leadingIcon: LucideIcons.paintBucket,
            semanticLabel: l10n.propertiesFill,
            onCommit: (JetColor? c) => onCommit(style.copyWith(fill: c)),
          ),
          const SizedBox(width: 6),
        ],
        _ColorField(
          keyBase: '$keyBase.stroke',
          value: style.stroke,
          allowNone: true,
          compact: true,
          leadingIcon: LucideIcons.pen,
          semanticLabel: l10n.propertiesOutline,
          onCommit: (JetColor? c) => onCommit(style.copyWith(stroke: c)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PresetDropdown(
            fieldKey: ValueKey<String>('$keyBase.strokeWidth'),
            triggerPreview: _LineWidthPreview(width: style.strokeWidth),
            label: _format(style.strokeWidth),
            tooltip: l10n.propertiesOutlineWidth,
            options: <_DropdownOption>[
              for (final double w in _strokeWidthPresets)
                _DropdownOption(
                  optionKey: ValueKey<String>(
                      '$keyBase.strokeWidth.option.${_format(w)}'),
                  label: _format(w),
                  preview: _LineWidthPreview(width: w),
                  selected: style.strokeWidth == w,
                  onPick: () => onCommit(style.copyWith(strokeWidth: w)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The panel's mirror of the planner's dominant default for the header role.
///
/// `CrosstabStyle.headerText` is read at two sites with different fallbacks
/// while unset: column headers centre, the single row-label stub column falls
/// back to [JetTextStyle.fallback] (left). The section displays the centred
/// one — column headers outnumber the one stub column — and the approximation
/// ends at the first edit, because an authored headerText is honoured at both
/// sites, alignment included.
///
/// Mirrored rather than imported: the render layer is not a designer
/// dependency and the panel must work with no data source attached. No single
/// test can assert the two copies are equal — they are private to different
/// libraries — so each side is pinned separately: the panel's value here by
/// `test/designer/crosstab_style_test.dart` ('the panel mirrors the planner
/// dominant defaults'), the planner's by
/// `test/rendering/crosstab/crosstab_planner_test.dart` ('an unstyled column
/// header centres its text' and the right-aligned cell-default pin).
const JetTextStyle _kCrosstabHeaderDefault =
    JetTextStyle(align: JetTextAlign.center);

/// The panel's mirror of the planner's BARE default for value cells — right
/// aligned, per spec A §3 — the value an unset slot falls back to only once
/// there is no styled layer above it. The Cells role falls back to this
/// directly. The Totals role does NOT: `_totalCellText`/`_cellBoxStyle` in
/// crosstab_planner.dart resolve an unset total VALUE style through
/// `style.cellText`/`cellBox` first, so the Totals role's effective value
/// (wired in `crosstab_inspector.dart`) is `cellText ?? _kCrosstabCellDefault`
/// — this constant only when Cells is unset too. (Total LABELS take the
/// left-aligned row-label style instead, the same dual fallback headerText
/// has.)
const JetTextStyle _kCrosstabCellDefault =
    JetTextStyle(align: JetTextAlign.right);

/// The label + inherited-hint/reset row shared by every crosstab appearance
/// role: the crosstab-level Header/Cells/Totals sections ([_crosstabRoleSection])
/// and the per-measure cell override (`_crosstabMeasureCard`).
///
/// Factored out on its own rather than forcing every caller through
/// [_crosstabRoleSection] itself, because the measure card's two editors keep
/// their own long-lived `cellText`/`cellBox` keyBases (predating this reset)
/// rather than the single shared keyBase the crosstab-level roles pass to
/// both editors — unifying that too would rename shipped, tested keys for no
/// behavioural gain.
///
/// The reset action appears only once at least one slot is set: an
/// always-visible reset on an untouched role would suggest state that is not
/// there.
Widget _crosstabStyleRoleHeader({
  required String label,
  required String resetKey,
  required bool authored,
  required VoidCallback onReset,
  required JetPrintLocalizations l10n,
  required ShadThemeData theme,
}) =>
    Row(
      children: <Widget>[
        Expanded(child: SectionLabel(label)),
        if (!authored)
          Text(l10n.crosstabStyleInherited,
              style: theme.textTheme.muted.copyWith(fontSize: 11))
        else
          _CardAction(
            actionKey: ValueKey<String>(resetKey),
            icon: LucideIcons.rotateCcw,
            tooltip: l10n.crosstabStyleReset,
            onPressed: onReset,
            theme: theme,
          ),
      ],
    );

/// One crosstab-level appearance role: its label, a text and a box editor,
/// and a reset that clears both slots back to inherited.
///
/// [text] and [box] are the authored slots — null means inherited, and the
/// editors then display [effectiveText] / [effectiveBox] so the controls are
/// never blank. Any edit commits a concrete style; [onReset] writes null back.
List<Widget> _crosstabRoleSection({
  required String label,
  required String keyBase,
  required JetTextStyle? text,
  required JetBoxStyle? box,
  required JetTextStyle effectiveText,
  required JetBoxStyle effectiveBox,
  required ValueChanged<JetTextStyle> onText,
  required ValueChanged<JetBoxStyle> onBox,
  required VoidCallback onReset,
  required JetPrintLocalizations l10n,
  required ShadThemeData theme,
}) {
  final bool authored = text != null || box != null;
  return <Widget>[
    const SizedBox(height: 12),
    _crosstabStyleRoleHeader(
      label: label,
      resetKey: '$keyBase.reset',
      authored: authored,
      onReset: onReset,
      l10n: l10n,
      theme: theme,
    ),
    _TextStyleEditor(
      keyBase: keyBase,
      style: text ?? effectiveText,
      onCommit: onText,
    ),
    const SizedBox(height: 4),
    _BoxStyleEditor(
      keyBase: keyBase,
      style: box ?? effectiveBox,
      onCommit: onBox,
    ),
  ];
}
