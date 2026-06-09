import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/report_element.dart';
import '../../controller/jet_report_designer_controller.dart';
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
class PropertiesPanel extends StatelessWidget {
  /// Creates the Properties panel body. Private to the library.
  const PropertiesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    final List<Widget> children;
    if (selection.isReport) {
      children = _reportInspector(controller, theme, l10n);
    } else if (selection.bandIndex case final int bandIndex) {
      children = _bandInspector(controller, bandIndex, theme, l10n);
    } else if (selection.singleOrNull case final String id
        when _find(controller, id) != null) {
      children =
          _elementInspector(controller, _find(controller, id)!, theme, l10n);
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
      ],
    ];
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
          onCommit: (double v) => controller.setBandHeight(index, v),
        ),
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
  });

  final Key fieldKey;
  final IconData prefix;
  final double value;
  final ValueChanged<double> onCommit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  });

  final Key fieldKey;
  final String value;
  final ValueChanged<String> onCommit;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
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

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
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
