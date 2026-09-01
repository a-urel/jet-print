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
/// a single undoable step (FR-013). The widget is stateless and holds no draft:
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
            _StyleToggleGroup(style: style, onCommit: onCommit),
            const SizedBox(width: 8),
            Expanded(
              child: _AlignSegments(
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
