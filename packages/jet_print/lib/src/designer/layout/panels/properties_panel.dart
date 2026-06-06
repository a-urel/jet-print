import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../region_chrome.dart';

/// The report's elements as a flat list, each paired with the glyph the toolbox
/// and outline use for that element kind so the three surfaces read as one tool.
/// Illustrative sample data this iteration (not localized), mirroring the
/// element instances shown in the Outline panel plus the `label1` element whose
/// sample properties this inspector edits.
const List<_ElementOption> _elementOptions = <_ElementOption>[
  _ElementOption(LucideIcons.type, 'label1'),
  _ElementOption(LucideIcons.type, 'Title'),
  _ElementOption(LucideIcons.table, 'OrdersTable'),
  _ElementOption(LucideIcons.hash, 'PageInfo'),
];

/// Body of the **Properties** tab: an editable property inspector shaped like
/// the one in a real report designer (FR-007). Name/value rows are grouped under
/// section labels and edited through shadcn controls only — text fields
/// ([ShadInput]), dropdowns ([ShadSelect]) and a boolean toggle ([ShadSwitch]).
/// Like the other right panels it has no header/title or hint text; the owning
/// tab already names it.
///
/// The values are illustrative sample data for a selected label element (not
/// localized) and the edits are local-only this iteration — nothing is bound to
/// a report model yet — but the controls are genuinely interactive so the panel
/// reads as a working inspector.
class PropertiesPanel extends StatefulWidget {
  /// Creates the Properties panel body. Private to the library.
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _ElementSelector(),
          const SizedBox(height: 10),
          const SectionLabel('Layout'),
          const _PropertyRow(
            label: 'Name',
            child: ShadInput(initialValue: 'label1'),
          ),
          const _PropertyRow(
            label: 'Location',
            child: _NumberPair(
              firstPrefix: _AxisIcon(LucideIcons.arrowRight),
              first: 10,
              secondPrefix: _AxisIcon(LucideIcons.arrowDown),
              second: 10,
            ),
          ),
          const _PropertyRow(
            label: 'Size',
            child: _NumberPair(
              firstPrefix: _AxisIcon(LucideIcons.moveHorizontal),
              first: 120,
              secondPrefix: _AxisIcon(LucideIcons.moveVertical),
              second: 24,
            ),
          ),
          const SizedBox(height: 10),
          const SectionLabel('Appearance'),
          const _PropertyRow(
            label: 'Font',
            child: _FontEditor(),
          ),
          const _PropertyRow(
            label: 'Text Align',
            child: _AlignToggle(),
          ),
          _PropertyRow(
            label: 'Visible',
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShadSwitch(
                value: _visible,
                onChanged: (bool v) => setState(() => _visible = v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One inspector row: a muted [label] on the leading edge and its editor [child]
/// filling the trailing space, vertically centered so controls of different
/// heights line up against their label.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, required this.child});

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
            width: 78,
            child: Text(
              label,
              style: theme.textTheme.muted.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Two compact numeric fields side by side, for the paired Location (X/Y axis
/// letters) and Size (width/height glyphs) properties. Each field carries a
/// muted leading [prefix] widget and its own increment/decrement stepper.
class _NumberPair extends StatelessWidget {
  const _NumberPair({
    required this.firstPrefix,
    required this.first,
    required this.secondPrefix,
    required this.second,
  });

  final Widget firstPrefix;
  final int first;
  final Widget secondPrefix;
  final int second;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _NumberField(prefix: firstPrefix, value: first)),
        const SizedBox(width: 8),
        Expanded(child: _NumberField(prefix: secondPrefix, value: second)),
      ],
    );
  }
}

/// A muted glyph for a numeric field's leading prefix — a position arrow for a
/// Location axis (X →, Y ↓) or a dimension glyph for a Size axis (width/height).
class _AxisIcon extends StatelessWidget {
  const _AxisIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: 14,
      color: ShadTheme.of(context).colorScheme.mutedForeground,
    );
  }
}

/// A compact numeric input: a muted leading [prefix] widget and a stacked up/down
/// [_Stepper] on the trailing edge that bumps the value by one. Local-only this
/// iteration (nothing is bound to a report model yet), but genuinely editable so
/// it reads as a working spin box.
class _NumberField extends StatefulWidget {
  const _NumberField({required this.prefix, required this.value});

  final Widget prefix;
  final int value;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _bump(int delta) {
    final int current = int.tryParse(_controller.text) ?? widget.value;
    _controller.text = '${current + delta}';
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: _controller,
      leading: widget.prefix,
      trailing: _Stepper(
        onIncrement: () => _bump(1),
        onDecrement: () => _bump(-1),
      ),
    );
  }
}

/// A pair of stacked chevron buttons (up over down) used as a numeric field's
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

/// One step chevron: a small, muted, tappable glyph with an opaque hit area so
/// the thin chevron is comfortable to press.
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

/// The Font editor: a family dropdown plus a narrow point-size field.
class _FontEditor extends StatelessWidget {
  const _FontEditor();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _Select(
            initialValue: 'Segoe UI',
            options: const <String>[
              'Segoe UI',
              'Arial',
              'Calibri',
              'Times New Roman',
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: _Select(
            initialValue: '9',
            options: const <String>[
              '8',
              '9',
              '10',
              '11',
              '12',
              '14',
              '16',
              '18',
              '20',
              '24',
              '28',
              '36',
              '48',
              '72',
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin wrapper over [ShadSelect] for a list of string [options], pre-built
/// with the option rows and a matching selected-value label. `minWidth: 0` lets
/// it shrink to the narrow inspector column instead of forcing a default width.
class _Select extends StatelessWidget {
  const _Select({required this.initialValue, required this.options});

  final String initialValue;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return ShadSelect<String>(
      initialValue: initialValue,
      minWidth: 0,
      options: <Widget>[
        for (final String option in options)
          ShadOption<String>(value: option, child: Text(option)),
      ],
      selectedOptionBuilder: (BuildContext context, String value) =>
          Text(value),
      onChanged: (_) {},
    );
  }
}

/// The object-selector dropdown at the top of the inspector: a flat list of the
/// report's elements, each row an element glyph beside its name, with the
/// selected element shown the same way in the closed control. It mirrors the
/// element picker atop a desktop report designer's property grid (DevExpress /
/// Telerik). Layout-only this iteration — selecting does not yet re-bind the
/// property rows below (FR-007), so `onChanged` is a stub.
class _ElementSelector extends StatelessWidget {
  const _ElementSelector();

  @override
  Widget build(BuildContext context) {
    return ShadSelect<String>(
      // Stable key: the test seam used to locate the selector without reaching
      // into private widget types (mirrored in the designer tests).
      key: const ValueKey<String>('jet_print.designer.elementSelector'),
      initialValue: _elementOptions.first.name,
      minWidth: 0,
      options: <Widget>[
        for (final _ElementOption option in _elementOptions)
          ShadOption<String>(
            value: option.name,
            child: _ElementOptionRow(option),
          ),
      ],
      selectedOptionBuilder: (BuildContext context, String value) =>
          _ElementOptionRow(_optionFor(value)),
      onChanged: (_) {},
    );
  }
}

/// The element matching [name] (falls back to the first option for an unknown
/// value, which cannot happen with the fixed sample list).
_ElementOption _optionFor(String name) {
  for (final _ElementOption option in _elementOptions) {
    if (option.name == name) return option;
  }
  return _elementOptions.first;
}

/// One selector entry: the element [option]'s glyph then its name, sized to read
/// like the Outline's element rows.
class _ElementOptionRow extends StatelessWidget {
  const _ElementOptionRow(this.option);

  final _ElementOption option;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(option.icon, size: 14, color: colors.mutedForeground),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            option.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Immutable description of one selectable report element (glyph + name).
class _ElementOption {
  const _ElementOption(this.icon, this.name);

  final IconData icon;
  final String name;
}

/// The Text Align editor as a single-select icon toggle group (Left / Center /
/// Right / Justify), shaped like the alignment control of a desktop designer's
/// inspector. It replaces the earlier dropdown: the four options are mutually
/// exclusive and map cleanly to glyphs, so a segmented button group reads faster
/// than a list. Selection is held locally this iteration — the active option is
/// the filled (primary) button, the rest are ghost buttons inside one bordered
/// group.
class _AlignToggle extends StatefulWidget {
  const _AlignToggle();

  @override
  State<_AlignToggle> createState() => _AlignToggleState();
}

class _AlignToggleState extends State<_AlignToggle> {
  static const List<_AlignOption> _options = <_AlignOption>[
    _AlignOption(LucideIcons.alignLeft, 'Left'),
    _AlignOption(LucideIcons.alignCenter, 'Center'),
    _AlignOption(LucideIcons.alignRight, 'Right'),
    _AlignOption(LucideIcons.alignJustify, 'Justify'),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < _options.length; i++)
                _AlignButton(
                  option: _options[i],
                  selected: i == _selected,
                  onTap: () => setState(() => _selected = i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One segment of the [_AlignToggle]: a tooltipped icon button rendered filled
/// (primary) when [selected] and ghost otherwise.
class _AlignButton extends StatelessWidget {
  const _AlignButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AlignOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget icon = Icon(option.icon, size: 16);
    return ShadTooltip(
      builder: (BuildContext context) => Text(option.label),
      child: selected
          ? ShadIconButton(
              icon: icon,
              width: 30,
              height: 30,
              onPressed: onTap,
            )
          : ShadIconButton.ghost(
              icon: icon,
              width: 30,
              height: 30,
              onPressed: onTap,
            ),
    );
  }
}

/// Immutable description of one alignment option (glyph + label).
class _AlignOption {
  const _AlignOption(this.icon, this.label);

  final IconData icon;
  final String label;
}
