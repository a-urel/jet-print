// Text and number entry fields + stepper.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

/// A plain single-line text field bound to a model string [value], committing
/// the trimmed text on Enter or blur — each commit one undoable model edit. Used
/// for the report's primary Name property and the group name/key fields. A blank
/// entry reverts to the current value (the report keeps a name); while the field
/// is focused the live value is never written over the user's in-progress text.
///
/// When [fields] is non-empty, a field-picker suffix button is shown; picking a
/// field inserts the `[field]` shorthand and commits immediately.
class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.fieldKey,
    required this.value,
    required this.placeholder,
    required this.onCommit,
    this.fields = const <FieldDef>[],
    this.pickerTooltip = '',
    this.pickerKeyPrefix = '',
  });

  final Key fieldKey;
  final String value;
  final String placeholder;
  final ValueChanged<String> onCommit;

  /// In-scope fields offered by an optional suffix picker; empty ⇒ no picker.
  /// Picking inserts the `[field]` shorthand (the caller compiles it).
  final List<FieldDef> fields;

  /// Tooltip for the picker button (used only when [fields] is non-empty).
  final String pickerTooltip;

  /// Key namespace for the picker test seam (used only when [fields] is non-empty).
  final String pickerKeyPrefix;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  final ShadPopoverController _picker = ShadPopoverController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect a model change made elsewhere (undo, rename via the toolbar), but
    // never clobber active typing.
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      _controller.text = widget.value; // keep the report named
      return;
    }
    if (text != widget.value) widget.onCommit(text);
  }

  void _pick(String field) {
    _picker.hide();
    _controller.text = '[$field]';
    _commit();
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
      onSubmitted: (_) => _commit(),
      trailing: widget.fields.isEmpty
          ? null
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

/// A numeric inspector field bound to a model [value]: it shows the live value,
/// commits a typed value on Enter or blur, and nudges by one via its stepper —
/// each commit a single undoable model edit. While the field is focused the
/// live value is not written over the user's in-progress text; an out-of-range
/// commit is reconciled by the model's clamp on the next rebuild. Non-numeric
/// input is rejected and the last valid value restored, with no commit.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.fieldKey,
    required this.prefix,
    required this.value,
    required this.onCommit,
    this.step = 1,
    this.focusNode,
  });

  final Key fieldKey;
  final IconData prefix;
  final double value;
  final ValueChanged<double> onCommit;

  /// The amount one stepper nudge adds or subtracts.
  final double step;

  /// An externally-owned focus node (the panel's double-tap focus target);
  /// null ⇒ the field owns a private one.
  final FocusNode? focusNode;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    // Reflect a model change made elsewhere, but never clobber active typing.
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final double? parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value); // reject unparseable input
      return;
    }
    // Ignore a re-commit that only reflects display rounding — e.g. blurring a
    // field showing the rounded "28.4" form of a 28.35 model value would
    // otherwise drift it to 28.4. Below display precision, there is no edit.
    if (_format(parsed) == _format(widget.value)) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onCommit(parsed);
  }

  void _bump(double delta) => widget.onCommit(widget.value + delta);

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
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
      onSubmitted: (_) => _commit(),
      leading: Icon(widget.prefix, size: 14, color: colors.mutedForeground),
      trailing: _Stepper(
        onIncrement: () => _bump(widget.step),
        onDecrement: () => _bump(-widget.step),
      ),
    );
  }
}

/// A pair of stacked chevron buttons (up over down) for a numeric field's
/// trailing affordance, nudging the value by one per tap.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.onIncrement, required this.onDecrement});

  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _StepButton(icon: LucideIcons.chevronUp, onTap: onIncrement),
        _StepButton(icon: LucideIcons.chevronDown, onTap: onDecrement),
      ],
    );
  }
}

/// One step chevron: a small, muted, tappable glyph with an opaque hit area.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(icon, size: 11, color: colors.mutedForeground),
    );
  }
}
