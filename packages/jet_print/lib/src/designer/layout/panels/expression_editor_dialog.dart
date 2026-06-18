/// The fx expression editor (032): a centered modal that composes a value-field
/// expression in the friendly template syntax, with field + function palettes
/// and live syntax/resolution feedback. Presentation only — it speaks the same
/// language as the inline field (`value_template_compiler`) and returns the
/// edited text for the caller to commit through its existing onCommit path.
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/binding_scope.dart';
import '../../../data/field_def.dart';
import '../../../expression/expression.dart';
import '../../l10n/jet_print_localizations.dart';
import '../../template/expression_function_catalog.dart';
import '../../template/value_template_compiler.dart';

const String _k = 'jet_print.designer.exprEditor';

/// Opens the expression editor seeded with [initialText]; returns the committed
/// text on Insert, or null on Cancel/dismiss. [resolvableNames] is the band's
/// resolvable name set (spec 031); [fields] is the in-scope field palette.
/// [descendantOperands] is the set of descendant leaf names valid as aggregate
/// operands (spec 033); [descendantFields] is the palette of marked deeper
/// field buttons.
Future<String?> showExpressionEditor(
  BuildContext context, {
  required String initialText,
  required Set<String> resolvableNames,
  required List<FieldDef> fields,
  Set<String> descendantOperands = const <String>{},
  List<FieldDef> descendantFields = const <FieldDef>[],
}) {
  return showShadDialog<String>(
    context: context,
    builder: (BuildContext context) => _ExpressionEditorDialog(
      initialText: initialText,
      resolvableNames: resolvableNames,
      fields: fields,
      descendantOperands: descendantOperands,
      descendantFields: descendantFields,
    ),
  );
}

/// The live verdict for the edited text.
sealed class EditorStatus {
  const EditorStatus();
}

/// The text is a well-formed binding with all refs in scope, or a plain literal.
class StatusValid extends EditorStatus {
  const StatusValid();
}

/// The text looks like a `{…}` binding but does not parse.
class StatusSyntaxError extends EditorStatus {
  const StatusSyntaxError();
}

/// The text is a well-formed binding but references the out-of-scope [name].
class StatusUnresolved extends EditorStatus {
  const StatusUnresolved(this.name);

  /// The first referenced field that is not in the resolvable name set.
  final String name;
}

/// Pure status computation, unit-testable independent of the widget.
/// - A binding (`{…}` / `[field]`): every `$F{}` ref must resolve — it is
///   resolvable when it is in [names], or when it is an aggregate operand and a
///   [descendantOperands] leaf (spec 033). A bare descendant ref (not an
///   aggregate operand) stays unresolved (FR-006). First out-of-scope ref →
///   unresolved(that name).
/// - A `{…}`-wrapped value that does NOT parse to a binding → syntax error.
/// - Plain literal text → valid.
EditorStatus statusFor(String text, Set<String> names,
    {Set<String> descendantOperands = const <String>{}}) {
  final ValueParse parse = parseValueField(text);
  if (parse is BindingValue) {
    Set<String> operandRefs;
    try {
      operandRefs = Expression.parse(parse.expression).aggregateOperandFields;
    } on Object {
      operandRefs = const <String>{};
    }
    for (final String ref in fieldRefsIn(parse.expression)) {
      if (names.contains(ref)) continue;
      if (operandRefs.contains(ref) && descendantOperands.contains(ref)) {
        continue;
      }
      return StatusUnresolved(ref);
    }
    return const StatusValid();
  }
  final String t = text.trim();
  if (t.length >= 2 && t.startsWith('{') && t.endsWith('}')) {
    return const StatusSyntaxError();
  }
  return const StatusValid();
}

class _ExpressionEditorDialog extends StatefulWidget {
  const _ExpressionEditorDialog({
    required this.initialText,
    required this.resolvableNames,
    required this.fields,
    this.descendantOperands = const <String>{},
    this.descendantFields = const <FieldDef>[],
  });

  final String initialText;
  final Set<String> resolvableNames;
  final List<FieldDef> fields;

  /// Descendant leaf names valid as aggregate operands (spec 033). Empty when
  /// no schema or the band has no nested collections.
  final Set<String> descendantOperands;

  /// Fx palette choices for descendant operands — rendered marked as deeper
  /// fields (FR-007). Empty when [descendantOperands] is empty.
  final List<FieldDef> descendantFields;

  @override
  State<_ExpressionEditorDialog> createState() =>
      _ExpressionEditorDialogState();
}

class _ExpressionEditorDialogState extends State<_ExpressionEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  EditorStatus _status = const StatusValid();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    _status = statusFor(_controller.text, widget.resolvableNames,
        descendantOperands: widget.descendantOperands);
  }

  void _onChange() => setState(() => _status = statusFor(
      _controller.text, widget.resolvableNames,
      descendantOperands: widget.descendantOperands));

  /// Inserts [snippet] at the caret (replacing any selection) and moves the
  /// caret to [caretInSnippet] within it.
  void _insertAtCaret(String snippet, int caretInSnippet) {
    final TextEditingValue v = _controller.value;
    final int start = v.selection.start < 0 ? v.text.length : v.selection.start;
    final int end = v.selection.end < 0 ? v.text.length : v.selection.end;
    final String next = v.text.replaceRange(start, end, snippet);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: (start + caretInSnippet).clamp(0, next.length),
      ),
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    return ShadDialog(
      title: Text(l10n.exprEditorTitle),
      actions: <Widget>[
        ShadButton.outline(
          key: const ValueKey<String>('$_k.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exprEditorCancel),
        ),
        ShadButton(
          key: const ValueKey<String>('$_k.insert'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.exprEditorInsert),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            ShadInput(
              key: const ValueKey<String>('$_k.input'),
              controller: _controller,
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 8),
            _StatusLine(status: _status, l10n: l10n),
            const SizedBox(height: 12),
            Text(l10n.exprEditorFieldsLabel),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final FieldDef f in widget.fields)
                  ShadButton.ghost(
                    key: ValueKey<String>('$_k.field.${f.name}'),
                    size: ShadButtonSize.sm,
                    onPressed: () =>
                        _insertAtCaret('[${f.name}]', '[${f.name}]'.length),
                    child: Text(f.name),
                  ),
                // Descendant leaves (spec 033) — valid only inside an aggregate.
                // Rendered marked (↳, italic) and tooltip'd as "deeper" so they
                // read distinctly from in-scope fields.
                for (final FieldDef f in widget.descendantFields)
                  ShadTooltip(
                    builder: (BuildContext context) =>
                        Text(l10n.exprEditorDeeperFieldHint),
                    child: ShadButton.ghost(
                      key: ValueKey<String>('$_k.deepField.${f.name}'),
                      size: ShadButtonSize.sm,
                      onPressed: () =>
                          _insertAtCaret('[${f.name}]', '[${f.name}]'.length),
                      child: Text('↳ ${f.name}',
                          style: const TextStyle(fontStyle: FontStyle.italic)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.exprEditorFunctionsLabel),
            const SizedBox(height: 4),
            _FunctionPalette(l10n: l10n, onPick: _insertAtCaret),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.l10n});
  final EditorStatus status;
  final JetPrintLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final (String text, Color color) = switch (status) {
      StatusValid() => (l10n.exprStatusValid, colors.primary),
      StatusSyntaxError() => (l10n.exprStatusSyntaxError, colors.destructive),
      StatusUnresolved(:final String name) => (
          l10n.exprStatusUnresolved(name),
          colors.destructive
        ),
    };
    return Text(text,
        key: const ValueKey<String>('$_k.status'),
        style: TextStyle(color: color, fontSize: 12));
  }
}

class _FunctionPalette extends StatelessWidget {
  const _FunctionPalette({required this.l10n, required this.onPick});
  final JetPrintLocalizations l10n;
  final void Function(String snippet, int caret) onPick;

  String _groupLabel(ExpressionFunctionGroup g) => switch (g) {
        ExpressionFunctionGroup.string => l10n.exprGroupString,
        ExpressionFunctionGroup.math => l10n.exprGroupMath,
        ExpressionFunctionGroup.logic => l10n.exprGroupLogic,
        ExpressionFunctionGroup.aggregate => l10n.exprGroupAggregate,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ExpressionFunctionGroup group
            in ExpressionFunctionGroup.values) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child:
                Text(_groupLabel(group), style: const TextStyle(fontSize: 11)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ExpressionFunction f in expressionFunctionCatalog)
                if (f.group == group)
                  ShadButton.ghost(
                    // MIN/MAX appear in BOTH math and aggregate groups — key by
                    // name AND group so the two buttons don't collide.
                    key: ValueKey<String>('$_k.fn.${f.name}.${group.name}'),
                    size: ShadButtonSize.sm,
                    onPressed: () => onPick(f.insertSnippet, f.caretOffset),
                    child: Text(f.name),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
