import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/report_element.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../designer_schema_scope.dart';
import '../../designer_scope.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../region_chrome.dart';

/// Stable test-seam key prefix for the inspector's fields and empty state.
const String _p = 'jet_print.designer.properties';

/// Body of the **Properties** tab: a context-aware inspector bound to the
/// controller (FR-007 / FR-019). It edits whatever is selected:
///
/// * a single **element** — its position (X/Y) and size (W/H) as live numeric
///   fields committed through `setGeometry`, plus its text (for a text element)
///   through `setText`; each edit is one undoable step;
/// * a **band** — its height through `setBandHeight`;
/// * the **report** — read-only page information (it is a fixed format);
/// * **nothing / a multi-selection** — a friendly empty state.
///
/// Every field reflects the live model, so a move/resize on the canvas updates
/// the numbers here, and an edit here updates the canvas — the two stay in sync
/// through the shared controller.
class PropertiesPanel extends StatefulWidget {
  /// Creates the Properties panel body. Private to the library.
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  /// Externally-owned focus nodes for the three double-tap focus targets, so a
  /// pending `requestPropertiesFocus` can land keyboard focus (the fields fall
  /// back to private nodes when none is supplied).
  final FocusNode _xFocus = FocusNode(debugLabel: 'jet_print.properties.x');
  final FocusNode _textFocus =
      FocusNode(debugLabel: 'jet_print.properties.text');
  final FocusNode _bandHeightFocus =
      FocusNode(debugLabel: 'jet_print.properties.bandHeight');

  @override
  void dispose() {
    _xFocus.dispose();
    _textFocus.dispose();
    _bandHeightFocus.dispose();
    super.dispose();
  }

  /// Consumes a pending properties-focus request after this frame settles (so
  /// the target field exists even when the tab body mounted this same frame)
  /// and moves keyboard focus to the most relevant field: the Text field (text
  /// element), the X field (any other element), or the height field (a band).
  /// The report has no editable field, so its request just brings the pane
  /// forward (the flag is still consumed). One-shot: `takePropertiesFocus`
  /// clears the flag, so ordinary rebuilds never re-steal focus. A report or
  /// multi-selection just consumes the request — no crash, no stuck flag.
  void _schedulePendingFocus(JetReportDesignerController controller) {
    if (!controller.pendingPropertiesFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.takePropertiesFocus()) return;
      final selection = controller.selection;
      if (selection.bandIndex != null) {
        _bandHeightFocus.requestFocus();
        return;
      }
      final String? id = selection.singleOrNull;
      if (id == null) return; // report (read-only) or a multi-selection
      final ReportElement? element = _find(controller, id);
      if (element == null) return;
      (element is TextElement ? _textFocus : _xFocus).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final JetDataSchema? schema = DesignerSchemaScope.of(context);
    final selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    _schedulePendingFocus(controller);

    final List<Widget> children;
    if (selection.isReport) {
      children = _reportInspector(controller, theme, l10n);
    } else if (selection.bandIndex case final int bandIndex) {
      children = _bandInspector(controller, bandIndex, theme, l10n);
    } else if (selection.singleOrNull case final String id
        when _find(controller, id) != null) {
      children = _elementInspector(
          controller, _find(controller, id)!, theme, l10n, schema);
    } else {
      return KeyedSubtree(
        key: const ValueKey<String>('$_p.empty'),
        child: _EmptyState(count: selection.length),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // --- Element ---------------------------------------------------------------

  List<Widget> _elementInspector(
    JetReportDesignerController controller,
    ReportElement element,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final String id = element.id;
    final JetRect b = element.bounds;
    return <Widget>[
      _Header(icon: _elementGlyph(element), title: id, theme: theme),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesPosition),
      Row(
        children: <Widget>[
          Expanded(
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.x'),
              prefix: LucideIcons.arrowRight,
              value: b.x,
              focusNode: _xFocus,
              onCommit: (double v) => controller.setGeometry(id, x: v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.y'),
              prefix: LucideIcons.arrowDown,
              value: b.y,
              onCommit: (double v) => controller.setGeometry(id, y: v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesSize),
      Row(
        children: <Widget>[
          Expanded(
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.width'),
              prefix: LucideIcons.moveHorizontal,
              value: b.width,
              onCommit: (double v) => controller.setGeometry(id, width: v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.height'),
              prefix: LucideIcons.moveVertical,
              value: b.height,
              onCommit: (double v) => controller.setGeometry(id, height: v),
            ),
          ),
        ],
      ),
      if (element is TextElement) ...<Widget>[
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesText),
        _TextField(
          fieldKey: const ValueKey<String>('$_p.field.text'),
          value: element.text,
          focusNode: _textFocus,
          onCommit: (String v) => controller.setText(id, v),
        ),
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesBinding),
        _BindingField(
          fieldKey: const ValueKey<String>('$_p.field.binding'),
          value: element.expression ?? '',
          placeholder: l10n.bindingExpressionHint,
          clearTooltip: l10n.bindingClearTooltip,
          onSet: (String v) => controller.setBinding(id, v),
          onClear: () => controller.clearBinding(id),
        ),
        if (element.expression case final String expr
            when _unresolved(schema, controller, id, expression: expr))
          _UnresolvedHint(message: l10n.bindingUnresolved),
      ],
      // Image binding: a field picker only (no expression) — FR-013 / U1.
      if (element is ImageElement) ...<Widget>[
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesBinding),
        _BindingField(
          fieldKey: const ValueKey<String>('$_p.field.imageBinding'),
          value: element.source is FieldImageSource
              ? (element.source as FieldImageSource).field
              : '',
          placeholder: l10n.bindingImageFieldHint,
          clearTooltip: l10n.bindingClearTooltip,
          onSet: (String v) => controller.setImageField(id, v),
          onClear: () => controller.setImageField(id, ''),
        ),
        if (element.source case final FieldImageSource s
            when s.field.isNotEmpty &&
                _unresolved(schema, controller, id, imageField: s.field))
          _UnresolvedHint(message: l10n.bindingUnresolved),
      ],
    ];
  }

  /// Whether [elementId]'s binding fails to resolve against the attached
  /// [schema] in its band scope (FR-018). With no schema attached, nothing is
  /// flagged — the token still shows, and resolution waits for a source
  /// (FR-019a).
  bool _unresolved(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId, {
    String? expression,
    String? imageField,
  }) {
    if (schema == null) return false;
    final List<int>? path = bandPathOfElement(controller.template, elementId);
    if (path == null) return false;
    final List<FieldDef> scope =
        fieldsInScopeAt(schema, controller.template, path);
    if (expression != null) return !expressionResolves(scope, expression);
    if (imageField != null) return !fieldResolves(scope, imageField);
    return false;
  }

  // --- Band ------------------------------------------------------------------

  List<Widget> _bandInspector(
    JetReportDesignerController controller,
    int index,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final double height = controller.template.bands[index].height;
    return <Widget>[
      _Header(
        icon: LucideIcons.rows3,
        title: bandTypeLabel(controller.template.bands[index].type, l10n),
        theme: theme,
      ),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesSize),
      _LabeledRow(
        label: l10n.propertiesHeight,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.bandHeight'),
          prefix: LucideIcons.moveVertical,
          value: height,
          focusNode: _bandHeightFocus,
          onCommit: (double v) => controller.setBandHeight(index, v),
        ),
      ),
      // Master/detail: designate the nested-collection field this band iterates
      // (US3 / FR-015). Addresses the selected top-level band as path [index].
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesBinding),
      _BindingField(
        fieldKey: const ValueKey<String>('$_p.field.bandCollection'),
        value: controller.template.bands[index].collectionField ?? '',
        placeholder: l10n.bindingCollectionHint,
        clearTooltip: l10n.bindingClearTooltip,
        onSet: (String v) => controller.setBandCollection(<int>[index], v),
        onClear: () => controller.setBandCollection(<int>[index], null),
      ),
    ];
  }

  // --- Report ----------------------------------------------------------------

  List<Widget> _reportInspector(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final page = controller.template.page;
    String pt(double v) => v.round().toString();
    return <Widget>[
      _Header(
          icon: LucideIcons.fileText, title: l10n.reportLabel, theme: theme),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesPage),
      _ReadonlyRow(
          label: l10n.propertiesSize,
          value: '${pt(page.width)} × ${pt(page.height)} pt'),
      _ReadonlyRow(
        label: l10n.propertiesMargins,
        value: '${pt(page.margins.left)} · ${pt(page.margins.top)} · '
            '${pt(page.margins.right)} · ${pt(page.margins.bottom)}',
      ),
    ];
  }

  ReportElement? _find(JetReportDesignerController controller, String id) {
    for (final band in controller.template.bands) {
      for (final ReportElement e in band.elements) {
        if (e.id == id) return e;
      }
    }
    return null;
  }
}

IconData _elementGlyph(ReportElement element) {
  if (element is TextElement) return LucideIcons.type;
  if (element is ShapeElement) return LucideIcons.square;
  if (element is ImageElement) return LucideIcons.image;
  if (element is BarcodeElement) return LucideIcons.barcode;
  return LucideIcons.square;
}

/// The inspector header: the selected object's glyph in a tinted tile beside its
/// name, so the panel always says what it is editing.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.theme});

  final IconData icon;
  final String title;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = theme.colorScheme;
    return Row(
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
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
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
            width: 64,
            child: Text(
              label,
              style:
                  theme.textTheme.muted.copyWith(color: colors.mutedForeground),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A read-only [label]/[value] row for informational properties (e.g. page size).
class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style:
                  theme.textTheme.muted.copyWith(color: colors.mutedForeground),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: theme.textTheme.small),
          ),
        ],
      ),
    );
  }
}

/// A numeric inspector field bound to a model [value]: it shows the live value,
/// commits a typed value on Enter or blur, and nudges by one via its stepper —
/// each commit a single undoable model edit. While the field is focused the
/// live value is not written over the user's in-progress text; an out-of-range
/// commit is reconciled by the model's clamp on the next rebuild.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.fieldKey,
    required this.prefix,
    required this.value,
    required this.onCommit,
    this.focusNode,
  });

  final Key fieldKey;
  final IconData prefix;
  final double value;
  final ValueChanged<double> onCommit;

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
    if (parsed != null) {
      widget.onCommit(parsed);
    } else {
      _controller.text = _format(widget.value); // reject unparseable input
    }
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
        onIncrement: () => _bump(1),
        onDecrement: () => _bump(-1),
      ),
    );
  }
}

/// A text inspector field bound to a model string [value]; commits on Enter/blur.
class _TextField extends StatefulWidget {
  const _TextField({
    required this.fieldKey,
    required this.value,
    required this.onCommit,
    this.focusNode,
  });

  final Key fieldKey;
  final String value;
  final ValueChanged<String> onCommit;

  /// An externally-owned focus node (the panel's double-tap focus target);
  /// null ⇒ the field owns a private one.
  final FocusNode? focusNode;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _controller.text != widget.value) {
      widget.onCommit(_controller.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
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
      onSubmitted: widget.onCommit,
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
  });

  final Key fieldKey;
  final String value;
  final String placeholder;
  final String clearTooltip;
  final ValueChanged<String> onSet;
  final VoidCallback onClear;

  @override
  State<_BindingField> createState() => _BindingFieldState();
}

class _BindingFieldState extends State<_BindingField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
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
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final String text = _controller.text.trim();
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

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
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
      trailing: Semantics(
        label: widget.clearTooltip,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _clear,
          child: Icon(LucideIcons.x, size: 14, color: colors.mutedForeground),
        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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

/// Formats a points value: a whole number drops its decimals, otherwise one.
String _format(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
