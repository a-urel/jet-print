// The value/visibility expression fields.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.fieldKey,
    required this.display,
    required this.placeholder,
    required this.fields,
    required this.pickerTooltip,
    required this.onCommit,
    this.fxTooltip = '',
    this.resolvableNames = const <String>{},
    this.showFx = true,
    this.pickerKeyPrefix = '$_p.field.value.pick',
    this.descendantOperands = const <String>{},
    this.descendantFields = const <FieldDef>[],
    this.focusNode,
  });

  final Key fieldKey;
  final ValueDisplay display;
  final String placeholder;

  /// The in-scope data-source fields offered by the suffix picker; empty ⇒ no
  /// picker button (no schema attached, or nothing in scope).
  final List<FieldDef> fields;

  /// Accessible label / tooltip for the suffix picker button.
  final String pickerTooltip;

  /// Accessible label / tooltip for the fx (expression editor) button.
  final String fxTooltip;

  /// Whether to show the fx (expression editor) affordance. Off for the barcode
  /// Data input, which is field-or-literal — no expressions (spec 036).
  final bool showFx;

  /// Key namespace for the field picker (so each reuse — value vs. barcode data
  /// — has its own stable test seam). Defaults to the value field's namespace.
  final String pickerKeyPrefix;

  /// The band's resolvable name set (schema fields in scope ∪ published totals,
  /// spec 031), passed to the fx editor so its unresolved check matches the
  /// inline field's. Empty ⇒ the editor stays silent (no schema/band).
  final Set<String> resolvableNames;
  final ValueChanged<String> onCommit;

  /// Descendant leaf names valid as aggregate operands (spec 033), forwarded to
  /// the fx editor so its status check accepts a deep aggregate. Empty ⇒ no
  /// schema/band, behavior unchanged.
  final Set<String> descendantOperands;

  /// The fx-palette choices for [descendantOperands] — rendered marked as
  /// deeper fields. Empty when [descendantOperands] is empty.
  final List<FieldDef> descendantFields;

  /// An externally-owned focus node (the panel's double-tap focus target);
  /// null ⇒ the field owns a private one.
  final FocusNode? focusNode;

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.display.text);
  final ShadPopoverController _picker = ShadPopoverController();
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_ValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    if (!_focus.hasFocus && widget.display.text != oldWidget.display.text) {
      _controller.text = widget.display.text;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _controller.text != widget.display.text) {
      widget.onCommit(_controller.text);
    }
  }

  /// Inserts [field] as a `[field]` binding — the same token a user could type —
  /// then closes the picker. The controller parses it to `$F{field}` in one
  /// undoable edit, so the field input and the picker share one code path.
  void _pick(String field) {
    _picker.hide();
    widget.onCommit('[$field]');
  }

  /// Opens the fx expression editor (032) seeded with the field's current text,
  /// and commits its result through the same `onCommit` path as the inline field
  /// — one undoable edit. Null (Cancel/dismiss) leaves the value untouched.
  Future<void> _openFx() async {
    final String? result = await showExpressionEditor(
      context,
      initialText: widget.display.text,
      resolvableNames: widget.resolvableNames,
      fields: widget.fields,
      descendantOperands: widget.descendantOperands,
      descendantFields: widget.descendantFields,
    );
    if (result != null) widget.onCommit(result);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _picker.dispose();
    _ownFocus?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      readOnly: !widget.display.editable,
      placeholder: Text(widget.placeholder),
      onSubmitted: widget.onCommit,
      // Editable values carry an fx affordance (opens the expression editor)
      // when [showFx]; the field picker rides beside it only when fields are in
      // scope. A read-only value (exotic/legacy binding), or an input with
      // neither affordance, keeps no trailing widget.
      trailing: !widget.display.editable ||
              (!widget.showFx && widget.fields.isEmpty)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.showFx)
                  Semantics(
                    label: widget.fxTooltip,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openFx,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          LucideIcons.squareFunction,
                          key: const ValueKey<String>('$_p.field.value.fx'),
                          size: 14,
                          color:
                              ShadTheme.of(context).colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                if (widget.fields.isNotEmpty)
                  _FieldPicker(
                    controller: _picker,
                    fields: widget.fields,
                    tooltip: widget.pickerTooltip,
                    onPick: _pick,
                    keyPrefix: widget.pickerKeyPrefix,
                  ),
              ],
            ),
    );
  }
}

/// The unified value field (013): one input for a text element's literal text or
/// its `[field]`/`{ … }` binding, shown exactly as the canvas token. It commits
/// the raw text on Enter/blur — the controller parses the three forms. A binding
/// that is outside the template grammar (legacy/exotic) is shown read-only via
/// [ValueDisplay.editable] so it is never silently lost (013 / FR-006a).
/// The Visible section control. Two states share one section:
///
/// * **static** (no expression) — a bare [ShadSwitch] on the left and an fx
///   button on the right that opens the expression editor. No row labels (the
///   "VISIBLE" section heading already names it).
/// * **expression** (a non-empty `visibleWhen`) — the switch is hidden and a
///   read-only field shows the expression, with an fx button (re-edit) and a
///   clear button that drops the expression back to the static switch.
///
/// Mirrors the Value field's fx affordance (spec 032). The field is read-only
/// because a visibility expression is only ever authored through the editor.
class _VisibleField extends StatefulWidget {
  const _VisibleField({
    required this.visible,
    required this.onChanged,
    required this.fxTooltip,
    required this.clearTooltip,
  });

  final BoolProperty visible;
  final ValueChanged<BoolProperty> onChanged;

  /// Accessible name / tooltip for the fx (expression editor) button.
  final String fxTooltip;

  /// Accessible name / tooltip for the clear-expression button.
  final String clearTooltip;

  @override
  State<_VisibleField> createState() => _VisibleFieldState();
}

class _VisibleFieldState extends State<_VisibleField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.visible.expression ?? '');

  @override
  void didUpdateWidget(_VisibleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String expr = widget.visible.expression ?? '';
    if (expr != _controller.text) _controller.text = expr;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opens the fx expression editor seeded with the current expression and
  /// commits its result (empty ⇒ clears, reverting to the static switch). Null
  /// (Cancel/dismiss) leaves the value untouched.
  Future<void> _openFx() async {
    final String? next = await showExpressionEditor(
      context,
      initialText: widget.visible.expression ?? '',
      resolvableNames: const <String>{},
      fields: const <FieldDef>[],
    );
    if (next == null) return;
    widget.onChanged(
        widget.visible.copyWith(expression: () => next.isEmpty ? null : next));
  }

  void _clear() =>
      widget.onChanged(widget.visible.copyWith(expression: () => null));

  Widget _fxButton(Color color) => Semantics(
        label: widget.fxTooltip,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openFx,
          child: Icon(
            LucideIcons.squareFunction,
            key: const ValueKey<String>('$_p.field.visibleWhen'),
            size: 16,
            color: color,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final String? expr = widget.visible.expression;
    final bool hasExpression = expr != null && expr.isNotEmpty;

    if (!hasExpression) {
      // Static: switch + fx affordance, no labels.
      return Row(
        children: <Widget>[
          ShadSwitch(
            key: const ValueKey<String>('$_p.field.visible'),
            value: widget.visible.value,
            onChanged: (bool v) =>
                widget.onChanged(widget.visible.copyWith(value: v)),
          ),
          const Spacer(),
          _fxButton(colors.mutedForeground),
        ],
      );
    }

    // Expression: read-only field showing it, with fx (edit) + clear buttons.
    return ShadInput(
      key: const ValueKey<String>('$_p.field.visibleExpression'),
      controller: _controller,
      readOnly: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _fxButton(colors.mutedForeground),
          const SizedBox(width: 6),
          Semantics(
            label: widget.clearTooltip,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clear,
              child: Icon(
                LucideIcons.x,
                key: const ValueKey<String>('$_p.field.visibleClear'),
                size: 14,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
