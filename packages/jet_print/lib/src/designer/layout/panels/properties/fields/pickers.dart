// Dropdown / field / format / binding pickers.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

/// One entry in a [_PresetDropdown]: a stable [optionKey], its display [label],
/// whether it is the current [selected] value (shows a check), and the [onPick]
/// to run when chosen.
class _DropdownOption {
  const _DropdownOption({
    required this.optionKey,
    required this.label,
    required this.selected,
    required this.onPick,
    this.labelStyle,
    this.preview,
  });

  final Key optionKey;
  final String label;
  final bool selected;
  final VoidCallback onPick;

  /// An optional style for the option's label — the family picker previews
  /// each font family in its own typeface (021 / C3). Null inherits the
  /// menu's default item style.
  final TextStyle? labelStyle;

  /// An optional preview shown trailing the label, filling the rest of the
  /// option's width — the outline-width picker draws a rule at each option's
  /// thickness. Null ⇒ label only.
  final Widget? preview;
}
/// A compact Office-style picker for the PAGE section: an outlined trigger
/// showing the current [label] with a chevron, that drops down a menu of
/// [options]. Reused for the paper-type and margin-preset pickers. The trigger
/// carries [fieldKey]; each option carries its own key, so widget tests can open
/// the menu and choose a specific entry. [tooltip] is the accessible name.
class _PresetDropdown extends StatefulWidget {
  const _PresetDropdown({
    required this.fieldKey,
    required this.label,
    required this.tooltip,
    required this.options,
    this.triggerPreview,
  });

  final Key fieldKey;
  final String label;
  final String tooltip;
  final List<_DropdownOption> options;

  /// An optional preview shown trailing the label in the trigger, filling the
  /// space up to the chevron — the outline-width picker draws a rule at the
  /// current thickness so the selected value reads visually, mirroring its
  /// option previews. When set, the label sizes to its content rather than
  /// expanding. Null ⇒ the label expands as usual.
  final Widget? triggerPreview;

  @override
  State<_PresetDropdown> createState() => _PresetDropdownState();
}
class _PresetDropdownState extends State<_PresetDropdown> {
  final ShadPopoverController _menu = ShadPopoverController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return ShadContextMenu(
      controller: _menu,
      // ShadContextMenu stacks its items in a non-scrolling Column, so a long
      // option list (e.g. a large font catalog) would overflow the viewport
      // unreachably. Wrap the items in a height-capped scroll view: short
      // preset lists stay un-scrolled, long ones scroll (022).
      items: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final _DropdownOption option in widget.options)
                  ShadContextMenuItem(
                    key: option.optionKey,
                    leading: Icon(
                      LucideIcons.check,
                      size: 16,
                      color: option.selected
                          ? colors.foreground
                          : colors.background,
                    ),
                    onPressed: () {
                      _menu.hide();
                      option.onPick();
                    },
                    child: option.preview == null
                        ? Text(option.label, style: option.labelStyle)
                        // A fixed width gives the trailing rule a stable span
                        // to fill, so the menu reads as one tidy column.
                        : SizedBox(
                            width: 140,
                            child: Row(
                              children: <Widget>[
                                Text(option.label, style: option.labelStyle),
                                const SizedBox(width: 12),
                                Expanded(child: option.preview!),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: ShadTooltip(
        builder: (BuildContext context) => Text(widget.tooltip),
        child: Semantics(
          label: widget.tooltip,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _menu.toggle,
            child: Container(
              key: widget.fieldKey,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: <Widget>[
                  // With a trailing preview the label sizes to its content and
                  // the preview takes the slack; otherwise the label expands.
                  if (widget.triggerPreview == null)
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small,
                      ),
                    )
                  else ...<Widget>[
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: widget.triggerPreview!),
                    const SizedBox(width: 8),
                  ],
                  Icon(LucideIcons.chevronDown,
                      size: 14, color: colors.mutedForeground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
/// The font sizes (points) the Font row's size picker offers, in ascending
/// order. A stored size outside this set still displays as the trigger label —
/// it is simply not check-marked, mirroring the family picker's handling of an
/// unavailable family. All entries sit inside the legacy [4, 144] bounds.
const List<double> _fontSizePresets = <double>[
  8,
  9,
  10,
  11,
  12,
  14,
  16,
  18,
  20,
  24,
  28,
  32,
  36,
  48,
  72,
  96,
];
/// The Value field's suffix affordance: a small database glyph that drops down a
/// menu of the in-scope data-source [fields]; choosing one inserts it as a
/// `[field]` binding through [onPick]. Each item carries the field's type glyph
/// (the same mapping the Data Source tree uses), so a field reads identically in
/// both places. Hidden entirely when no fields are in scope.
class _FieldPicker extends StatelessWidget {
  const _FieldPicker({
    required this.controller,
    required this.fields,
    required this.tooltip,
    required this.onPick,
    this.keyPrefix = '$_p.field.value.pick',
  });

  final ShadPopoverController controller;
  final List<FieldDef> fields;
  final String tooltip;
  final ValueChanged<String> onPick;

  /// Key namespace for the trigger glyph and each option, so each reuse of the
  /// picker (Value field, band/image binding) has its own stable test seam.
  /// Defaults to the Value field's namespace.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ShadContextMenu(
      controller: controller,
      // A single scrollable, searchable body rather than one raw item per field:
      // ShadContextMenu lays its items in a non-scrolling Column, so a long
      // schema would overflow off-screen with no way to reach the lower fields.
      items: <Widget>[
        _FieldPickerMenu(
          fields: fields,
          keyPrefix: keyPrefix,
          onPick: onPick,
        ),
      ],
      child: Semantics(
        label: tooltip,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.toggle,
          child: Icon(
            LucideIcons.database,
            key: ValueKey<String>(keyPrefix),
            size: 14,
            color: colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
/// The scrollable, searchable body of the field picker. A search box filters the
/// fields by a case-insensitive substring match on the name, and the matches sit
/// in a height-capped scroll view so a large schema stays reachable. Each match
/// keeps the `$keyPrefix.$name` key the flat menu used, so its stable test seam
/// (and the field-type glyph) is unchanged.
class _FieldPickerMenu extends StatefulWidget {
  const _FieldPickerMenu({
    required this.fields,
    required this.keyPrefix,
    required this.onPick,
  });

  final List<FieldDef> fields;
  final String keyPrefix;
  final ValueChanged<String> onPick;

  @override
  State<_FieldPickerMenu> createState() => _FieldPickerMenuState();
}
class _FieldPickerMenuState extends State<_FieldPickerMenu> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final String q = _query.trim().toLowerCase();
    final List<FieldDef> matches = q.isEmpty
        ? widget.fields
        : <FieldDef>[
            for (final FieldDef f in widget.fields)
              if (f.name.toLowerCase().contains(q)) f,
          ];
    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: ShadInput(
              key: ValueKey<String>('${widget.keyPrefix}.search'),
              autofocus: true,
              placeholder: const Text('Search fields'),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'No matching fields',
                style: TextStyle(fontSize: 13, color: colors.mutedForeground),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final FieldDef field in matches)
                      ShadContextMenuItem(
                        key: ValueKey<String>(
                            '${widget.keyPrefix}.${field.name}'),
                        leading: Icon(fieldTypeGlyph(field.type), size: 16),
                        onPressed: () => widget.onPick(field.name),
                        child: Text(field.name),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
/// The Format field (013): a free-text ICU pattern bound to `TextElement.format`,
/// committed on Enter/blur, with a suffix button that drops down the quick-pick
/// [presets] (mirroring the Value field's field picker). Picking a preset fills
/// the pattern in; None clears it. When the bound value's [fieldType] is known,
/// presets that cannot apply to it are shown disabled.
class _FormatField extends StatefulWidget {
  const _FormatField({
    required this.fieldKey,
    required this.value,
    required this.placeholder,
    required this.presets,
    required this.fieldType,
    required this.pickerTooltip,
    required this.onCommit,
  });

  final Key fieldKey;
  final String value;
  final String placeholder;
  final List<FormatPreset> presets;

  /// The type of the bound field, or null when the value is literal / a template
  /// / out of scope — null leaves every preset enabled.
  final JetFieldType? fieldType;

  /// Accessible label / tooltip for the suffix preset-picker button.
  final String pickerTooltip;
  final ValueChanged<String> onCommit;

  @override
  State<_FormatField> createState() => _FormatFieldState();
}
class _FormatFieldState extends State<_FormatField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final ShadPopoverController _picker = ShadPopoverController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_FormatField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _controller.text != widget.value) {
      widget.onCommit(_controller.text);
    }
  }

  /// Fills the field with [preset]'s pattern (empty for None ⇒ clear) and closes
  /// the dropdown — one undoable edit through the same commit path as typing.
  void _pick(FormatPreset preset) {
    _picker.hide();
    _controller.text = preset.pattern;
    widget.onCommit(preset.pattern);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _picker.dispose();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      placeholder: Text(widget.placeholder),
      onSubmitted: widget.onCommit,
      trailing: _FormatPicker(
        controller: _picker,
        presets: widget.presets,
        fieldType: widget.fieldType,
        tooltip: widget.pickerTooltip,
        onPick: _pick,
      ),
    );
  }
}
/// The Format field's suffix affordance: a small dropdown glyph that opens a
/// menu of the quick-pick [presets]; choosing one fills its pattern through
/// [onPick]. Presets that cannot apply to the bound value's [fieldType] are
/// rendered disabled (numeric patterns on a date value, etc.); a null/unknown
/// type leaves every preset enabled.
class _FormatPicker extends StatelessWidget {
  const _FormatPicker({
    required this.controller,
    required this.presets,
    required this.fieldType,
    required this.tooltip,
    required this.onPick,
  });

  final ShadPopoverController controller;
  final List<FormatPreset> presets;
  final JetFieldType? fieldType;
  final String tooltip;
  final ValueChanged<FormatPreset> onPick;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ShadContextMenu(
      controller: controller,
      items: <Widget>[
        for (final FormatPreset preset in presets)
          ShadContextMenuItem(
            key: ValueKey<String>('$_p.field.format.preset.${preset.label}'),
            enabled: preset.enabledFor(fieldType),
            onPressed: () => onPick(preset),
            child: Text(preset.label),
          ),
      ],
      child: Semantics(
        label: tooltip,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.toggle,
          child: Icon(
            LucideIcons.hash,
            key: const ValueKey<String>('$_p.field.format.pick'),
            size: 14,
            color: colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
/// A data-binding inspector field (US2 / FR-009, FR-012, FR-013): an input
/// holding the current binding ([value] — a text element's expression or an
/// image element's field), with a trailing clear affordance. Committing a
/// non-empty value calls [onSet]; committing empty, or tapping clear, calls
/// [onClear]. Each commit is one undoable model edit through the controller.
class _BindingField extends StatefulWidget {
  const _BindingField({
    required this.fieldKey,
    required this.value,
    required this.placeholder,
    required this.clearTooltip,
    required this.onSet,
    required this.onClear,
    this.fields = const <FieldDef>[],
    this.pickerTooltip = '',
    this.pickerKeyPrefix = '',
  });

  final Key fieldKey;
  final String value;
  final String placeholder;
  final String clearTooltip;
  final ValueChanged<String> onSet;
  final VoidCallback onClear;

  /// In-scope data-source fields offered by an optional suffix picker (the same
  /// affordance the Value field carries); empty ⇒ no picker button, leaving the
  /// plain free-text binding field. A band binding offers its collection fields,
  /// an image binding its scalar fields.
  final List<FieldDef> fields;

  /// Accessible label / tooltip for the suffix picker button (used only when
  /// [fields] is non-empty).
  final String pickerTooltip;

  /// Key namespace for the suffix picker, so the band and image bindings each
  /// get a distinct test seam (used only when [fields] is non-empty).
  final String pickerKeyPrefix;

  @override
  State<_BindingField> createState() => _BindingFieldState();
}
class _BindingFieldState extends State<_BindingField> {
  /// Wraps a stored bare field name as the `[name]` shorthand for display.
  static String _wrap(String v) => v.isEmpty ? '' : '[$v]';

  /// Strips a surrounding `[ ]` to recover the bare field name on commit.
  static String _strip(String v) {
    final String t = v.trim();
    return t.length >= 2 && t.startsWith('[') && t.endsWith(']')
        ? t.substring(1, t.length - 1).trim()
        : t;
  }

  late final TextEditingController _controller =
      TextEditingController(text: _wrap(widget.value));
  final ShadPopoverController _picker = ShadPopoverController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_BindingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _wrap(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final String text = _strip(_controller.text);
    if (text.isEmpty) {
      if (widget.value.isNotEmpty) widget.onClear();
    } else if (text != widget.value) {
      widget.onSet(text);
    }
  }

  void _clear() {
    _controller.clear();
    widget.onClear();
  }

  /// Sets [field] as the binding — the bare field name (a band binding names a
  /// collection, an image binding a scalar) — and closes the picker. One
  /// undoable edit through the same `onSet` path typing commits.
  void _pick(String field) {
    _picker.hide();
    _controller.text = _wrap(field);
    if (field != widget.value) widget.onSet(field);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _picker.dispose();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      placeholder: Text(widget.placeholder),
      onSubmitted: (_) => _commit(),
      // With in-scope fields the input shows the same data-field picker the
      // Value field carries; the picker supersedes the clear affordance
      // (emptying the field still clears the binding). Without a picker, the
      // plain clear (×) stays as the only way to drop the binding.
      trailing: widget.fields.isEmpty
          ? Semantics(
              label: widget.clearTooltip,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
                child: Icon(LucideIcons.x,
                    size: 14, color: colors.mutedForeground),
              ),
            )
          : _FieldPicker(
              controller: _picker,
              fields: widget.fields,
              tooltip: widget.pickerTooltip,
              keyPrefix: widget.pickerKeyPrefix,
              onPick: _pick,
            ),
    );
  }
}
