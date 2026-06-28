// Small layout chrome for the Properties panel.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

/// The inspector header: the selected object's glyph in a tinted tile beside its
/// name, so the panel always says what it is editing.
///
/// When [onEditingStart] is supplied the header is interactive: tapping the
/// glyph+label row calls [onEditingStart] and the parent flips [editing] to
/// `true`, swapping the static [Text] for an [EditableLabel] inline field.
/// Call sites that pass no editing params (e.g. the group sub-header, the
/// column-layout section header) get the original read-only behaviour.
class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.theme,
    this.rawName,
    this.fallback,
    this.editing = false,
    this.onEditingStart,
    this.onEditingEnd,
    this.onCommit,
  });

  final IconData icon;
  final String title;
  final ShadThemeData theme;

  /// The raw stored name used to pre-fill the rename field (null → empty).
  final String? rawName;

  /// The placeholder shown in the empty rename field (the type-level fallback).
  final String? fallback;

  /// Whether the inline rename field is currently shown.
  final bool editing;

  /// Called when the user taps the label area to begin renaming. If null the
  /// header is read-only (no tap target, no field).
  final VoidCallback? onEditingStart;

  /// Called when editing ends (after commit or Esc cancel).
  final VoidCallback? onEditingEnd;

  /// Called with the trimmed new name (or null for empty) on commit.
  final ValueChanged<String?>? onCommit;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    final TextStyle labelStyle =
        theme.textTheme.small.copyWith(fontWeight: FontWeight.w600);

    // EditableLabel's inline TextField requires a Material ancestor.  The
    // designer is hosted in a ShadApp (not MaterialApp), so we inject a
    // transparent Material locally — zero visual effect, pure ancestor seam.
    final Widget labelArea = Expanded(
      child: Material(
        type: MaterialType.transparency,
        child: EditableLabel(
          key: const ValueKey<String>('$_p.header'),
          display: title,
          value: rawName,
          placeholder: fallback ?? title,
          editing: editing,
          onEditingEnd: onEditingEnd,
          onCommit: onCommit ?? (_) {},
          textStyle: labelStyle,
        ),
      ),
    );

    final Widget row = Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: colors.foreground),
        ),
        const SizedBox(width: 8),
        labelArea,
      ],
    );

    if (onEditingStart != null && !editing) {
      return GestureDetector(onTap: onEditingStart, child: row);
    }
    return row;
  }
}

/// A compact inline warning row: a small alert glyph plus muted destructive
/// text, used to flag an unbound list where the author edits it.
class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.text, required this.theme});

  final String text;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(LucideIcons.triangleAlert, size: 13, color: colors.destructive),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: theme.textTheme.muted.copyWith(color: colors.destructive)),
        ),
      ],
    );
  }
}

/// A compact inline informational notice row: a small info glyph plus muted
/// secondary text, used for non-error status messages such as an inactive layout.
/// Visually distinct from [_InlineWarning] (neutral/muted rather than destructive).
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text, required this.theme});

  final String text;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(LucideIcons.info, size: 13, color: colors.mutedForeground),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: theme.textTheme.muted
                  .copyWith(color: colors.mutedForeground)),
        ),
      ],
    );
  }
}

/// The "Add column layout" affordance. Disabled (greyed, non-tappable) when the
/// report shape can't host a label grid, wrapped in a tooltip that explains the
/// requirement (spec 035 / FR-003). Enabled, it commits a default layout.
class _ColumnLayoutAddButton extends StatelessWidget {
  const _ColumnLayoutAddButton({
    required this.enabled,
    required this.label,
    required this.disabledTooltip,
    required this.onAdd,
  });

  final bool enabled;
  final String label;
  final String disabledTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final Widget button = ShadButton.outline(
      key: const ValueKey<String>('$_p.field.columnLayoutAdd'),
      size: ShadButtonSize.sm,
      enabled: enabled,
      onPressed: enabled ? onAdd : null,
      leading: const Icon(LucideIcons.columns3, size: 14),
      // Flex child prevents the inner Row from overflowing the panel at narrow
      // panel widths (the panel minimum is ~280 px; the label may be longer).
      child: Flexible(
        child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
    );
    final Widget content = enabled
        ? button
        : ShadTooltip(builder: (_) => Text(disabledTooltip), child: button);
    // Align to intrinsic width: the parent Column uses CrossAxisAlignment.stretch,
    // so without this wrapper both buttons expand to full panel width.
    return Align(alignment: Alignment.centerLeft, child: content);
  }
}

/// The "Remove column layout" affordance — restores a plain detail band.
class _ColumnLayoutRemoveButton extends StatelessWidget {
  const _ColumnLayoutRemoveButton(
      {required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.ghost(
          key: const ValueKey<String>('$_p.field.columnLayoutRemove'),
          size: ShadButtonSize.sm,
          onPressed: onRemove,
          leading: const Icon(LucideIcons.trash2, size: 14),
          // Flex child prevents the inner Row from overflowing at narrow widths.
          child: Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ),
      );
}

/// A labelled inspector row: a muted [label] on the leading edge and its editor
/// [child] filling the trailing space.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              // Smaller than the body muted style so the common property labels
              // (Symbology, Show text, Quiet zone, Column spacing…) fit on one
              // line in the narrow label column instead of wrapping.
              style: theme.textTheme.muted
                  .copyWith(color: colors.mutedForeground, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A small inline warning shown beneath a binding whose field is missing from
/// (or out of scope in) the attached data source (FR-018) — a triangle glyph
/// plus the localized message, in the theme's destructive color.
class _UnresolvedHint extends StatelessWidget {
  const _UnresolvedHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final Color color = theme.colorScheme.destructive;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(LucideIcons.triangleAlert, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.muted.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when nothing editable is selected: a centered glyph and a short hint
/// (or a count when several elements are selected).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.count});

  /// The number of selected elements (>1 ⇒ multi-selection).
  final int count;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final String message = count > 1
        ? l10n.propertiesMultiSelected(count)
        : l10n.propertiesEmptyHint;
    return RegionEmptyHint(icon: LucideIcons.mousePointer2, message: message);
  }
}
