import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/band.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/group_level.dart';
import '../../../domain/page_format.dart';
import '../../../domain/report_band.dart' show BandType;
import '../../../domain/report_element.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../../rendering/elements/shape_path.dart';
import '../../../rendering/frame/primitive.dart';
import '../../../rendering/text/font_registry.dart';
import '../../../rendering/text/ui_font_family.dart';
import '../../controller/band_walker.dart';
import '../../controller/binding_resolution.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../designer_font_scope.dart';
import '../../designer_schema_scope.dart';
import '../../designer_scope.dart';
import '../../field_type_glyph.dart';
import '../../format_presets.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../../margin_presets.dart';
import '../../paper_presets.dart';
import '../../template/value_template_compiler.dart';
import '../region_chrome.dart';
import 'expression_editor_dialog.dart';

part 'style_editors.dart';

/// Stable test-seam key prefix for the inspector's fields and empty state.
const String _p = 'jet_print.designer.properties';

/// A text element whose whole expression is exactly one `$F{field}` reference —
/// a simple field binding, the only form whose value type the Format picker
/// infers (functions/CONCAT templates produce a transformed value, so they
/// leave every preset enabled).
final RegExp _simpleFieldRef = RegExp(r'^\$F\{([^{}]+)\}$');

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

  /// Whether the user has put the paper-type picker into **Custom** mode,
  /// revealing the width/height fields. View-only state (never serialized): the
  /// page itself may match a preset's dimensions yet still be edited as Custom.
  /// The custom fields also appear whenever the live page matches no preset.
  bool _customPaper = false;

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
      if (selection.bandId != null) {
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
    } else if (selection.bandId case final String bandId) {
      children = _bandInspector(controller, bandId, theme, l10n, schema);
    } else if (selection.groupId case final String groupId
        when findGroup(controller.definition, groupId) != null) {
      children = _groupInspector(controller, groupId, theme, l10n);
    } else if (selection.scopeId case final String scopeId
        when findScope(controller.definition, scopeId) != null) {
      children = _scopeInspector(controller, scopeId, theme, l10n, schema);
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
        SectionLabel(l10n.propertiesValue),
        _ValueField(
          fieldKey: const ValueKey<String>('$_p.field.value'),
          display: element.expression == null
              ? ValueDisplay(element.text)
              : reverseCompile(element.expression!),
          placeholder: l10n.valueFieldHint,
          focusNode: _textFocus,
          fields: _valueFieldChoices(schema, controller, id),
          pickerTooltip: l10n.valueFieldPickerTooltip,
          fxTooltip: l10n.valueFieldFxTooltip,
          resolvableNames: _resolvableNames(schema, controller, id),
          onCommit: (String v) => controller.setValue(id, v),
        ),
        if (element.expression case final String expr
            when _unresolved(schema, controller, id, expression: expr))
          _UnresolvedHint(message: l10n.bindingUnresolved),
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesFormat),
        _FormatField(
          fieldKey: const ValueKey<String>('$_p.field.format'),
          value: element.format ?? '',
          placeholder: l10n.formatHint,
          presets: formatPresets(l10n),
          fieldType:
              _boundFieldType(schema, controller, id, element.expression),
          pickerTooltip: l10n.formatPresetPickerTooltip,
          onCommit: (String v) => controller.setFormat(id, v),
        ),
        const SizedBox(height: 12),
        // Font section (021 / US1): every editor reads the element's effective
        // style and commits one whole-style copyWith through setTextStyle —
        // one undoable step per committed change (FR-013). Keyed by element id
        // so a selection switch rebuilds the editors, discarding uncommitted
        // input (C9).
        KeyedSubtree(
          key: ValueKey<String>('$_p.font.$id'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(l10n.propertiesFont),
              const SizedBox(height: 4),
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
                      style: element.style,
                      onCommit: (JetTextStyle next) =>
                          controller.setTextStyle(id, next),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 84,
                    child: _PresetDropdown(
                      fieldKey: const ValueKey<String>('$_p.field.fontSize'),
                      label: _format(element.style.fontSize),
                      tooltip: l10n.fontSizeLabel,
                      options: <_DropdownOption>[
                        for (final double size in _fontSizePresets)
                          _DropdownOption(
                            optionKey: ValueKey<String>(
                                '$_p.field.fontSize.option.${_format(size)}'),
                            label: _format(size),
                            selected: element.style.fontSize == size,
                            onPick: () => controller.setTextStyle(
                                id, element.style.copyWith(fontSize: size)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ColorField(
                    keyBase: '$_p.field.textColor',
                    value: element.style.color,
                    compact: true,
                    onCommit: (JetColor? c) => controller.setTextStyle(
                        id, element.style.copyWith(color: c)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  _StyleToggleGroup(
                    style: element.style,
                    onCommit: (JetTextStyle next) =>
                        controller.setTextStyle(id, next),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AlignSegments(
                      align: element.style.align,
                      onCommit: (JetTextAlign a) => controller.setTextStyle(
                          id, element.style.copyWith(align: a)),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        if (element.source case final FieldImageSource s
            when s.field.isNotEmpty &&
                _unresolved(schema, controller, id, imageField: s.field))
          _UnresolvedHint(message: l10n.bindingUnresolved),
      ],
      // Barcode color (021 / US3): the shared color editor — no None, bars
      // always have a color — bound to BarcodeElement.color through one
      // setBarcodeColor commit per pick (C8). The placeholder rendering (and
      // later the real bars) reflects it on canvas/preview/export.
      if (element is BarcodeElement) ...<Widget>[
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>('$_p.barcode.$id'),
          child: _LabeledRow(
            label: l10n.propertiesColor,
            child: _ColorField(
              keyBase: '$_p.field.barcodeColor',
              value: element.color,
              onCommit: (JetColor? c) => controller.setBarcodeColor(id, c!),
            ),
          ),
        ),
      ],
      // Shape gallery: pick the form from a visual roster (020 / FR-001/002).
      // Shape-gated, so it is absent for text/image/barcode and for no/multi
      // selection (the latter fall through to the empty state before this runs).
      if (element is ShapeElement) ...<Widget>[
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesShape),
        _ShapeGallery(controller: controller, element: element),
        const SizedBox(height: 12),
        // Appearance section (021 / US2): fill (closed forms only — a line has
        // no interior), outline color with None, and outline width 0–20 (0
        // hides the outline, the color stays remembered). Each commit is one
        // copyWith + one setShapeStyle = one undo step (FR-013). Keyed by
        // element id so a selection switch discards uncommitted input (C9).
        KeyedSubtree(
          key: ValueKey<String>('$_p.appearance.$id'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(l10n.propertiesAppearance),
              const SizedBox(height: 4),
              // Fill, outline and width share one label-less row. The two color
              // boxes are compact swatches distinguished by a leading glyph
              // (bucket = fill, square = outline); a line has no interior, so it
              // drops the fill box. Width fills the remaining width.
              Row(
                children: <Widget>[
                  if (element.kind != ShapeKind.line) ...<Widget>[
                    _ColorField(
                      keyBase: '$_p.field.fill',
                      value: element.style.fill,
                      allowNone: true,
                      compact: true,
                      leadingIcon: LucideIcons.paintBucket,
                      semanticLabel: l10n.propertiesFill,
                      onCommit: (JetColor? c) => controller.setShapeStyle(
                          id, element.style.copyWith(fill: c)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _ColorField(
                    keyBase: '$_p.field.stroke',
                    value: element.style.stroke,
                    allowNone: true,
                    compact: true,
                    leadingIcon: LucideIcons.pen,
                    semanticLabel: l10n.propertiesOutline,
                    onCommit: (JetColor? c) => controller.setShapeStyle(
                        id, element.style.copyWith(stroke: c)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _PresetDropdown(
                      fieldKey: const ValueKey<String>('$_p.field.strokeWidth'),
                      triggerPreview:
                          _LineWidthPreview(width: element.style.strokeWidth),
                      label: _format(element.style.strokeWidth),
                      tooltip: l10n.propertiesOutlineWidth,
                      options: <_DropdownOption>[
                        for (final double w in _strokeWidthPresets)
                          _DropdownOption(
                            optionKey: ValueKey<String>(
                                '$_p.field.strokeWidth.option.${_format(w)}'),
                            label: _format(w),
                            preview: _LineWidthPreview(width: w),
                            selected: element.style.strokeWidth == w,
                            onPick: () => controller.setShapeStyle(
                                id, element.style.copyWith(strokeWidth: w)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// The scalar fields the Value field's picker offers for [elementId]: every
  /// field in the element's band scope except nested collections (a label binds
  /// a single value, not a whole collection). Each carries its [FieldDef.type]
  /// so the picker can show the same type glyph as the Data Source tree. Empty
  /// when no schema is attached or the element sits in no resolvable band — the
  /// picker button then hides, leaving the plain free-text value field.
  List<FieldDef> _valueFieldChoices(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
  ) {
    if (schema == null) return const <FieldDef>[];
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return const <FieldDef>[];
    return resolvableFieldChoices(controller.definition, schema, band.id);
  }

  /// The group key shown in the inspector: a simple `$F{field}` reads as the
  /// editable `[field]` shorthand; any other expression (a composite, or the
  /// placeholder constant) is shown verbatim and editable (NOT the read-only
  /// `{…}` token `reverseCompile` would produce).
  String _groupKeyDisplay(String key) {
    final ValueDisplay d = reverseCompile(key);
    return d.editable ? d.text : key;
  }

  /// Maps the group-key field input to a stored 005a expression: a `[field]`
  /// shorthand compiles to `$F{field}`; any other input is the expression
  /// verbatim (it is already 005a, e.g. `$F{x}`, `YEAR($F{date})`, `0`).
  String _compileKey(String input) => switch (parseValueField(input)) {
        BindingValue(:final String expression) => expression,
        LiteralValue(:final String text) => text,
      };

  /// The scalar (non-collection) fields a group key can reference, resolved at
  /// the group's header (or footer) band level — the scalar counterpart of the
  /// list collection picker.
  List<FieldDef> _groupKeyChoices(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    GroupLevel group,
  ) {
    if (schema == null) return const <FieldDef>[];
    final String? bandId = group.header?.id ?? group.footer?.id;
    if (bandId == null) return const <FieldDef>[];
    final List<DetailScope> chain =
        scopePathToBand(controller.definition, bandId);
    return <FieldDef>[
      for (final FieldDef f in fieldsInScopeForChain(schema, chain))
        if (f.type != JetFieldType.collection) f,
    ];
  }

  /// The type of the field a text element binds, when its value is a single
  /// `[field]` binding to a field of known type in scope — used to gate the
  /// Format presets to the ones that can apply. Returns null (every preset
  /// stays enabled) for a literal value, an advanced `{ … }` template, an
  /// out-of-scope/unknown field, or no attached schema: the value's type is not
  /// pinned down, so the designer is not restricted.
  JetFieldType? _boundFieldType(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
    String? expression,
  ) {
    if (schema == null || expression == null) return null;
    final RegExpMatch? simple = _simpleFieldRef.firstMatch(expression);
    if (simple == null) return null;
    final String name = simple.group(1)!;
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return null;
    for (final FieldDef f
        in resolvableFieldChoices(controller.definition, schema, band.id)) {
      if (f.name == name) return f.type;
    }
    return null;
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
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return false;
    final Set<String> names =
        resolvableNamesForBand(controller.definition, schema, band.id);
    if (expression != null) return !expressionResolvesNames(names, expression);
    if (imageField != null) return !names.contains(imageField);
    return false;
  }

  /// The resolvable name set for [elementId]'s band — schema fields in scope plus
  /// published totals (spec 031). Empty when no schema/band, so the fx editor's
  /// unresolved check stays silent exactly like the inline field.
  Set<String> _resolvableNames(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
  ) {
    if (schema == null) return const <String>{};
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return const <String>{};
    return resolvableNamesForBand(controller.definition, schema, band.id);
  }

  // --- Band ------------------------------------------------------------------
  // A band inspector edits only what belongs to the band itself: its height.
  // The group's key + pagination flags live in the Group inspector, and a
  // scope's collection in the Scope inspector — so a flag is never shown on both
  // a group header and footer band (the 023 two-bands smell, fixed by spec 024).

  List<Widget> _bandInspector(
    JetReportDesignerController controller,
    String bandId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final Band? band = findBand(controller.definition, bandId);
    if (band == null) return const <Widget>[];
    final List<Widget> children = <Widget>[
      _Header(
        icon: LucideIcons.rows3,
        title: bandTypeLabel(band.type, l10n),
        theme: theme,
      ),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesSize),
      // Label-less, like the element SIZE row: the vertical-arrow glyph stands
      // in for the dropped "Height" label.
      _NumberField(
        fieldKey: const ValueKey<String>('$_p.field.bandHeight'),
        prefix: LucideIcons.moveVertical,
        value: band.height,
        focusNode: _bandHeightFocus,
        onCommit: (double v) => controller.setBandHeight(bandId, v),
      ),
    ];
    if (band.type == BandType.detail) {
      children
        ..add(const SizedBox(height: 18))
        ..addAll(_bandListSection(controller, bandId, theme, l10n, schema));
    }
    // A group's key + pagination flags are edited from the band the author
    // sees: its group HEADER band — or its FOOTER when the group has no header,
    // so the flags are never unreachable (2026-06-14 design note). Exactly one
    // band per group carries the section.
    final GroupLevel? group = findGroupOfBand(controller.definition, bandId);
    if (group != null && (group.header?.id ?? group.footer?.id) == bandId) {
      children
        ..add(const SizedBox(height: 18))
        ..add(_Header(
          icon: LucideIcons.group,
          title: '${l10n.propertiesGroup} · ${group.name}',
          theme: theme,
        ))
        ..add(const SizedBox(height: 14))
        ..addAll(_groupSection(controller, group.id, theme, l10n, schema));
    }
    return children;
  }

  // --- Group (first-class entity; its flags are edited from its header band) -
  //
  // The group's key + the three pagination flags are edited from the group's
  // carrier band via [_groupSection] (see [_bandInspector]), not from this
  // abstract node. Selecting the group row shows a read-only summary that points
  // the author to the group header band (2026-06-14 design note).

  List<Widget> _groupInspector(
    JetReportDesignerController controller,
    String groupId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final GroupLevel? group = findGroup(controller.definition, groupId);
    if (group == null) return const <Widget>[];
    return <Widget>[
      _Header(icon: LucideIcons.group, title: group.name, theme: theme),
      const SizedBox(height: 12),
      Text(
        l10n.propertiesGroupOnHeaderHint,
        style: theme.textTheme.muted
            .copyWith(color: theme.colorScheme.mutedForeground),
      ),
    ];
  }

  /// The group's editable name + key (with field picker) + the three pagination
  /// flags, surfaced on the group's carrier band by [_bandInspector]. Each edit
  /// writes through to the one [GroupLevel] — the single source of truth
  /// (spec 024 / C11).
  List<Widget> _groupSection(
    JetReportDesignerController controller,
    String groupId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final GroupLevel? group = findGroup(controller.definition, groupId);
    if (group == null) return const <Widget>[];
    return <Widget>[
      SectionLabel(l10n.propertiesGroupName),
      const SizedBox(height: 8),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.groupName'),
        value: group.name,
        placeholder: l10n.propertiesGroupName,
        onCommit: (String v) => controller.setGroupName(groupId, v),
      ),
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesGroupKey),
      const SizedBox(height: 8),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.groupKey'),
        value: _groupKeyDisplay(group.key),
        placeholder: l10n.bindingExpressionHint,
        fields: _groupKeyChoices(schema, controller, group),
        pickerTooltip: l10n.bindingFieldPickerTooltip,
        pickerKeyPrefix: '$_p.field.groupKey.pick',
        onCommit: (String v) => controller.setGroupKey(groupId, _compileKey(v)),
      ),
      const SizedBox(height: 12),
      // keepTogether + reprintHeaderOnEachPage are implemented and golden-tested
      // but hidden from the UI for now (2026-06-14 design note) — only
      // start-new-page is surfaced. The controller setters remain available.
      ShadSwitch(
        key: const ValueKey<String>('$_p.field.groupNewPage'),
        value: group.startNewPage,
        onChanged: (bool v) => controller.setGroupStartNewPage(groupId, v),
        label: Text(l10n.propertiesGroupNewPage),
      ),
    ];
  }

  // --- Scope (the collection a detail scope iterates) ------------------------

  List<Widget> _scopeInspector(
    JetReportDesignerController controller,
    String scopeId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final DetailScope? scope = findScope(controller.definition, scopeId);
    if (scope == null) return const <Widget>[];
    final bool isRoot = controller.definition.body.root.id == scopeId;
    return <Widget>[
      _Header(
          icon: LucideIcons.rows3, title: l10n.propertiesScope, theme: theme),
      // The master/root scope iterates the records themselves and carries no
      // collection field; only a nested scope binds one (US3 / FR-015).
      if (!isRoot) ...<Widget>[
        const SizedBox(height: 14),
        SectionLabel(l10n.propertiesBinding),
        _BindingField(
          fieldKey: const ValueKey<String>('$_p.field.scopeCollection'),
          value: scope.collectionField ?? '',
          placeholder: l10n.bindingCollectionHint,
          clearTooltip: l10n.bindingClearTooltip,
          fields: _scopeCollectionChoices(schema, controller, scopeId),
          pickerTooltip: l10n.bindingFieldPickerTooltip,
          pickerKeyPrefix: '$_p.field.scopeCollection.pick',
          onSet: (String v) => controller.setScopeCollection(scopeId, v),
          onClear: () => controller.setScopeCollection(scopeId, null),
        ),
        if ((scope.collectionField ?? '').isEmpty) ...<Widget>[
          const SizedBox(height: 6),
          _InlineWarning(text: l10n.bindingCollectionMissing, theme: theme),
        ],
      ],
    ];
  }

  /// The collection fields a nested scope can iterate (US3 / FR-015): the
  /// collection-typed fields in its PARENT scope's field scope (a scope binds a
  /// whole collection). Empty when no schema is attached, hiding the picker.
  List<FieldDef> _scopeCollectionChoices(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String scopeId,
  ) {
    if (schema == null) return const <FieldDef>[];
    // Descend the schema through every ANCESTOR scope (excluding this scope's
    // own collectionField), then offer the collections available at that level.
    final List<DetailScope> chain =
        scopePathToScope(controller.definition, scopeId);
    final List<DetailScope> ancestors = chain.isEmpty
        ? const <DetailScope>[]
        : chain.sublist(0, chain.length - 1);
    return <FieldDef>[
      for (final FieldDef f in fieldsInScopeForChain(schema, ancestors))
        if (f.type == JetFieldType.collection) f,
    ];
  }

  /// The "List" section on a DETAIL band (Surface A): the collection its
  /// enclosing scope iterates, editable where the author looks. A root-scope
  /// detail band shows a read-only "main dataset" label (the root iterates the
  /// records themselves, no collection field); a nested-list detail band shows
  /// the same schema-aware binding picker the scope inspector uses, plus an
  /// inline warning when the list is unbound.
  List<Widget> _bandListSection(
    JetReportDesignerController controller,
    String bandId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final DetailScope? scope = findScopeOfBand(controller.definition, bandId);
    if (scope == null) return const <Widget>[];
    final bool isRoot = controller.definition.body.root.id == scope.id;
    if (isRoot) {
      return <Widget>[
        SectionLabel(l10n.propertiesList),
        const SizedBox(height: 8),
        Text(l10n.propertiesListRootSource, style: theme.textTheme.muted),
      ];
    }
    return <Widget>[
      SectionLabel(l10n.propertiesList),
      const SizedBox(height: 8),
      _BindingField(
        fieldKey: const ValueKey<String>('$_p.field.bandCollection'),
        value: scope.collectionField ?? '',
        placeholder: l10n.bindingCollectionHint,
        clearTooltip: l10n.bindingClearTooltip,
        fields: _scopeCollectionChoices(schema, controller, scope.id),
        pickerTooltip: l10n.bindingFieldPickerTooltip,
        pickerKeyPrefix: '$_p.field.bandCollection.pick',
        onSet: (String v) => controller.setScopeCollection(scope.id, v),
        onClear: () => controller.setScopeCollection(scope.id, null),
      ),
      if ((scope.collectionField ?? '').isEmpty) ...<Widget>[
        const SizedBox(height: 6),
        _InlineWarning(text: l10n.bindingCollectionMissing, theme: theme),
      ],
    ];
  }

  // --- Report ----------------------------------------------------------------

  List<Widget> _reportInspector(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final PageFormat page = controller.definition.page;
    final PaperMatch paper = recognizePaper(page);
    final MarginMatch margin = recognizeMargin(page.margins);
    final bool landscape = page.width > page.height;
    // The page is edited as Custom when it matches no preset, or when the user
    // explicitly chose Custom from the picker (revealing the W/H fields).
    final bool customMode = paper.isCustom || _customPaper;
    return <Widget>[
      _Header(
          icon: LucideIcons.fileText, title: l10n.reportLabel, theme: theme),
      const SizedBox(height: 14),
      // The report's primary identity: its name, committed through `rename` as
      // one undoable step. A blank entry reverts so the report stays named.
      SectionLabel(l10n.propertiesName),
      const SizedBox(height: 8),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.reportName'),
        value: controller.definition.name,
        placeholder: l10n.reportNameHint,
        onCommit: controller.rename,
      ),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesPage),
      const SizedBox(height: 8),
      // Paper type: named by the matching preset (with its size) or Custom,
      // resizing the page through setPageFormat while preserving the current
      // margins (US1). Label-less — the picker's value and tooltip name it.
      _PresetDropdown(
        fieldKey: const ValueKey<String>('$_p.field.paper'),
        label: customMode ? l10n.propertiesCustom : paper.label!,
        tooltip: l10n.paperPickerTooltip,
        options: <_DropdownOption>[
          for (final PaperPreset preset in kPaperPresets)
            _DropdownOption(
              optionKey:
                  ValueKey<String>('$_p.field.paper.option.${preset.name}'),
              label: paperPresetLabel(preset),
              selected: !customMode && paper.name == preset.name,
              onPick: () {
                setState(() => _customPaper = false);
                controller.setPageFormat(applyPaper(preset,
                    landscape: landscape, margins: page.margins));
              },
            ),
          // Custom: keep the current dimensions but reveal the W/H fields so
          // the user can type exact values (US3).
          _DropdownOption(
            optionKey: const ValueKey<String>('$_p.field.paper.option.Custom'),
            label: l10n.propertiesCustom,
            selected: customMode,
            onPick: () => setState(() => _customPaper = true),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Orientation: derived from width vs height; toggling swaps them (US3).
      _OrientationToggle(
        landscape: landscape,
        portraitLabel: l10n.orientationPortrait,
        landscapeLabel: l10n.orientationLandscape,
        onChanged: (bool wantLandscape) {
          if (wantLandscape == landscape) return;
          controller.setPageFormat(
              page.copyWith(width: page.height, height: page.width));
        },
      ),
      const SizedBox(height: 12),
      _PagePreview(page: page),
      // Custom width/height: shown only in Custom mode (US3). The controller
      // clamps a sub-minimum dimension; the field reverts non-numeric input.
      if (customMode) ...<Widget>[
        const SizedBox(height: 8),
        // Width and height share one label-less row (their directional glyphs
        // stand in for the dropped labels, as the element SIZE row does).
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                fieldKey: const ValueKey<String>('$_p.field.pageWidth'),
                prefix: LucideIcons.moveHorizontal,
                value: page.width,
                onCommit: (double v) => controller.setPageFormat(
                    controller.definition.page.copyWith(width: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                fieldKey: const ValueKey<String>('$_p.field.pageHeight'),
                prefix: LucideIcons.moveVertical,
                value: page.height,
                onCommit: (double v) => controller.setPageFormat(
                    controller.definition.page.copyWith(height: v)),
              ),
            ),
          ],
        ),
      ],
      // Margins: a preset picker that writes all four sides, plus per-side
      // fields. Editing any side yields an uneven set that reads Custom (US2).
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesMargins),
      const SizedBox(height: 4),
      _PresetDropdown(
        fieldKey: const ValueKey<String>('$_p.field.marginPreset'),
        label: margin.isCustom
            ? l10n.propertiesCustom
            : _marginPresetLabel(margin.kind!, l10n),
        tooltip: l10n.marginPickerTooltip,
        options: <_DropdownOption>[
          for (final MarginPreset preset in kMarginPresets)
            _DropdownOption(
              optionKey: ValueKey<String>(
                  '$_p.field.marginPreset.option.${preset.kind.name}'),
              label: _marginPresetLabel(preset.kind, l10n),
              selected: margin.kind == preset.kind,
              onPick: () => controller.setPageFormat(controller.definition.page
                  .copyWith(margins: JetEdgeInsets.all(preset.value))),
            ),
        ],
      ),
      const SizedBox(height: 8),
      // Margins in two label-less rows — horizontal (left/right), then vertical
      // (top/bottom); the directional arrows stand in for the dropped labels.
      Row(
        children: <Widget>[
          Expanded(
            child: _marginField(
                controller,
                'marginLeft',
                LucideIcons.arrowLeft,
                page.margins.left,
                (JetEdgeInsets m, double v) => m.copyWith(left: v)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _marginField(
                controller,
                'marginRight',
                LucideIcons.arrowRight,
                page.margins.right,
                (JetEdgeInsets m, double v) => m.copyWith(right: v)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: _marginField(
                controller,
                'marginTop',
                LucideIcons.arrowUp,
                page.margins.top,
                (JetEdgeInsets m, double v) => m.copyWith(top: v)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _marginField(
                controller,
                'marginBottom',
                LucideIcons.arrowDown,
                page.margins.bottom,
                (JetEdgeInsets m, double v) => m.copyWith(bottom: v)),
          ),
        ],
      ),
    ];
  }

  /// One per-side margin [_NumberField] (label-less; its arrow [prefix] names
  /// the side) that commits the edited side through `setPageFormat`, composing
  /// the next margins from the live page so concurrent edits never race on a
  /// stale capture. [edit] applies the typed value to the right side; the field
  /// reverts invalid input to the last valid.
  Widget _marginField(
    JetReportDesignerController controller,
    String keySuffix,
    IconData prefix,
    double value,
    JetEdgeInsets Function(JetEdgeInsets margins, double value) edit,
  ) {
    return _NumberField(
      fieldKey: ValueKey<String>('$_p.field.$keySuffix'),
      prefix: prefix,
      value: value,
      onCommit: (double v) {
        final PageFormat p = controller.definition.page;
        controller.setPageFormat(p.copyWith(margins: edit(p.margins, v)));
      },
    );
  }

  /// The localized display name for a margin [kind].
  String _marginPresetLabel(
          MarginPresetKind kind, JetPrintLocalizations l10n) =>
      switch (kind) {
        MarginPresetKind.normal => l10n.marginPresetNormal,
        MarginPresetKind.narrow => l10n.marginPresetNarrow,
        MarginPresetKind.wide => l10n.marginPresetWide,
        MarginPresetKind.none => l10n.marginPresetNone,
      };

  ReportElement? _find(JetReportDesignerController controller, String id) {
    final Band? band = findBandOfElement(controller.definition, id);
    if (band == null) return null;
    for (final ReportElement e in band.elements) {
      if (e.id == id) return e;
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

/// The Office-style page sample in the PAGE section (018): a proportional sheet
/// drawn at the live page's aspect ratio, with a guide rectangle marking the
/// content area (the page inset by its margins). Purely schematic inspector
/// chrome — it reads the same [PageFormat] the canvas/preview/export render, so
/// it always agrees with them, but it is **not** itself a report renderer. It
/// rebuilds whenever the page changes (size, orientation, or a margin).
class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.page});

  final PageFormat page;

  // The preview depicts physical paper, so it uses a fixed light palette in
  // both themes (a page reads as paper, not as the dark inspector surface) —
  // like a print-preview thumbnail.
  static const Color _paper = Color(0xFFFFFFFF);
  static const Color _paperBorder = Color(0xFFCBD5E1); // slate-300
  static const Color _guideColor = Color(0xFF64748B); // slate-500

  /// The preview frame (px) the page is drawn within.
  static const double _frame = 150;

  /// Points mapped to [_frame] px — A4's long side, so the default page nearly
  /// fills the frame and other sizes read relative to it.
  static const double _referenceSide = 842;

  @override
  Widget build(BuildContext context) {
    // Guard against a degenerate page (the controller clamps to a positive
    // page, but a raw model could be malformed) so the sizing stays finite.
    final double pw = page.width <= 0 ? 1.0 : page.width;
    final double ph = page.height <= 0 ? 1.0 : page.height;
    // Scale points→px so the preview's *size* tracks the page — a larger page
    // reads larger, a smaller one smaller — not just its proportions (US3).
    const double scale = _frame / _referenceSide;
    double w = pw * scale;
    double h = ph * scale;
    // Keep the sheet inside the frame: a page past the reference is fitted down
    // with its proportions preserved.
    final double longest = w > h ? w : h;
    if (longest > _frame) {
      w = w * _frame / longest;
      h = h * _frame / longest;
    }
    return SizedBox(
      key: const ValueKey<String>('$_p.pagePreview'),
      height: _frame,
      child: Center(
        child: SizedBox(
          width: w,
          height: h,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double sheetW = constraints.maxWidth;
              final double sheetH = constraints.maxHeight;
              // The margins map to the same fractions of the scaled sheet, so
              // the guide insets track the real content area proportionally.
              final double l = sheetW * page.margins.left / page.width;
              final double t = sheetH * page.margins.top / page.height;
              final double r = sheetW * page.margins.right / page.width;
              final double b = sheetH * page.margins.bottom / page.height;
              return Stack(
                children: <Widget>[
                  // The paper sheet.
                  Positioned.fill(
                    child: Container(
                      key: const ValueKey<String>('$_p.pagePreview.sheet'),
                      decoration: BoxDecoration(
                        color: _paper,
                        border: Border.all(color: _paperBorder),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The visible margin chrome: faint shading over the margin
                  // band and a dashed frame around the printable content area,
                  // so even small margins read clearly.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PagePreviewPainter(
                        page: page,
                        guideColor: _guideColor,
                      ),
                    ),
                  ),
                  // A transparent box sized to the content area — the stable
                  // test seam for the guide insets (the painter draws the chrome).
                  Positioned(
                    left: l,
                    top: t,
                    right: r,
                    bottom: b,
                    child: const SizedBox.expand(
                      key: ValueKey<String>('$_p.pagePreview.guide'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints the page preview's margin chrome over the sheet: a faint wash over the
/// margin band and a dashed frame around the printable content area, both scaled
/// from the live [PageFormat]'s margins. Schematic only — the canvas/preview/
/// export remain the source of truth for the actual render.
class _PagePreviewPainter extends CustomPainter {
  const _PagePreviewPainter({required this.page, required this.guideColor});

  final PageFormat page;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double l = size.width * page.margins.left / page.width;
    final double t = size.height * page.margins.top / page.height;
    final double r = size.width * page.margins.right / page.width;
    final double b = size.height * page.margins.bottom / page.height;
    final Rect content = Rect.fromLTRB(l, t, size.width - r, size.height - b);
    if (content.width <= 0 || content.height <= 0) return;

    // Wash the margin band (the sheet minus the content area) so the printable
    // area stands out even when the margins are small.
    final Path band = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(content),
    );
    canvas.drawPath(band, Paint()..color = const Color(0x14000000));

    // Dashed frame around the content area — the margin guide.
    final Paint guide = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _dashedRect(canvas, content, guide);
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    _dashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _dashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _dashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _dashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const double dash = 3, gap = 2;
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      final double end = (d + dash) < total ? d + dash : total;
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) =>
      old.page != page || old.guideColor != guideColor;
}

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
        onIncrement: () => _bump(1),
        onDecrement: () => _bump(-1),
      ),
    );
  }
}

/// The orientation toggle in the PAGE section (018): a two-segment
/// Portrait | Landscape control in the iOS-style tray (mirroring the workspace
/// mode switch). The active segment reads as a raised tile and is inert;
/// selecting the other emits [onChanged] with the requested orientation, which
/// the panel turns into a width/height swap. Orientation is derived from the
/// page (never stored), so the active segment always reflects the live page.
class _OrientationToggle extends StatelessWidget {
  const _OrientationToggle({
    required this.landscape,
    required this.portraitLabel,
    required this.landscapeLabel,
    required this.onChanged,
  });

  final bool landscape;
  final String portraitLabel;
  final String landscapeLabel;

  /// Fires with the requested orientation (`true` = landscape) when the inactive
  /// segment is selected.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('$_p.field.orientation'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          _segment(
            theme: theme,
            segmentKey:
                const ValueKey<String>('$_p.field.orientation.portrait'),
            icon: LucideIcons.rectangleVertical,
            label: portraitLabel,
            active: !landscape,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          _segment(
            theme: theme,
            segmentKey:
                const ValueKey<String>('$_p.field.orientation.landscape'),
            icon: LucideIcons.rectangleHorizontal,
            label: landscapeLabel,
            active: landscape,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required ShadThemeData theme,
    required Key segmentKey,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    final Color fg = active ? colors.foreground : colors.mutedForeground;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? null : onTap, // selecting the active mode is a no-op
          child: Container(
            key: segmentKey,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? colors.background : const Color(0x00000000),
              borderRadius: BorderRadius.circular(6),
              boxShadow: active
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The unified value field (013): one input for a text element's literal text or
/// its `[field]`/`{ … }` binding, shown exactly as the canvas token. It commits
/// the raw text on Enter/blur — the controller parses the three forms. A binding
/// that is outside the template grammar (legacy/exotic) is shown read-only via
/// [ValueDisplay.editable] so it is never silently lost (013 / FR-006a).
class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.fieldKey,
    required this.display,
    required this.placeholder,
    required this.fields,
    required this.pickerTooltip,
    required this.fxTooltip,
    required this.resolvableNames,
    required this.onCommit,
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

  /// The band's resolvable name set (schema fields in scope ∪ published totals,
  /// spec 031), passed to the fx editor so its unresolved check matches the
  /// inline field's. Empty ⇒ the editor stays silent (no schema/band).
  final Set<String> resolvableNames;
  final ValueChanged<String> onCommit;

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
      // Editable values carry an fx affordance (opens the expression editor);
      // the field picker rides beside it only when fields are in scope. A
      // read-only value (exotic/legacy binding) keeps no trailing affordances.
      trailing: !widget.display.editable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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
                  ),
              ],
            ),
    );
  }
}

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
      items: <Widget>[
        for (final FieldDef field in fields)
          ShadContextMenuItem(
            key: ValueKey<String>('$keyPrefix.${field.name}'),
            leading: Icon(fieldTypeGlyph(field.type), size: 16),
            onPressed: () => onPick(field.name),
            child: Text(field.name),
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

/// The outline widths (points) the Appearance row's width picker offers, in
/// ascending order. 0 hides the outline (the color stays remembered). A stored
/// width outside this set still displays as the trigger label. All entries sit
/// inside the legacy [0, 20] bounds.
const List<double> _strokeWidthPresets = <double>[
  0,
  0.5,
  1,
  1.5,
  2,
  3,
  4,
  6,
  8,
  12,
  16,
  20,
];

/// A full-width preview of a stroke [width]: a horizontal rule that fills the
/// space it is given, drawn at the width's thickness (capped to the box so
/// heavy widths stay legible — the numeric label carries the exact value). A
/// width of 0 draws nothing, reading as "no outline". Used by the Appearance
/// row's width picker, trailing the number in both the trigger and the options.
class _LineWidthPreview extends StatelessWidget {
  const _LineWidthPreview({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 16,
      child: Center(
        child: Container(
          width: double.infinity,
          height: width.clamp(0, 14).toDouble(),
          decoration: BoxDecoration(
            color: colors.foreground,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

/// Formats a points value: a whole number drops its decimals, otherwise one.
String _format(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

/// The localized accessible name for a shape [kind] (020 / FR-012).
String _shapeFormLabel(ShapeKind kind, JetPrintLocalizations l10n) =>
    switch (kind) {
      ShapeKind.line => l10n.shapeFormLine,
      ShapeKind.rectangle => l10n.shapeFormRectangle,
      ShapeKind.ellipse => l10n.shapeFormEllipse,
      ShapeKind.triangle => l10n.shapeFormTriangle,
      ShapeKind.diamond => l10n.shapeFormDiamond,
      ShapeKind.pentagon => l10n.shapeFormPentagon,
      ShapeKind.hexagon => l10n.shapeFormHexagon,
      ShapeKind.star => l10n.shapeFormStar,
    };

/// The closed forms the gallery offers, in roster order.
///
/// [ShapeKind.line] is intentionally absent: a corner-to-corner diagonal is not
/// a useful authoring primitive (a report rule is drawn with a thin rectangle).
/// Line stays a valid `ShapeKind` — pre-existing line elements still load and
/// render unchanged — it is simply not offered here.
const List<ShapeKind> _galleryForms = <ShapeKind>[
  ShapeKind.rectangle,
  ShapeKind.ellipse,
  ShapeKind.triangle,
  ShapeKind.diamond,
  ShapeKind.pentagon,
  ShapeKind.hexagon,
  ShapeKind.star,
];

/// The shape form gallery (020 / US1): a wrap of the [_galleryForms] thumbnails,
/// each drawing its form through the **same** `shapePath` geometry the renderer
/// uses, so the picker icon is exactly what the canvas, preview, and export
/// produce. The thumbnail matching the element's current [ShapeElement.kind] is
/// highlighted — unless the shape carries a preserved [ShapeElement.unknownForm]
/// (it renders as a rectangle, but that is a fallback, not a deliberate choice),
/// or the element is a legacy [ShapeKind.line] (outside the roster), in which
/// case nothing is highlighted. Tapping a thumbnail commits `setShapeKind`;
/// re-picking the active form is a no-op the controller absorbs.
class _ShapeGallery extends StatelessWidget {
  const _ShapeGallery({required this.controller, required this.element});

  final JetReportDesignerController controller;
  final ShapeElement element;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    // A preserved unknown form (or a legacy line) highlights nothing.
    final ShapeKind? active = element.unknownForm == null ? element.kind : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final ShapeKind kind in _galleryForms)
          _ShapeThumbnail(
            kind: kind,
            label: _shapeFormLabel(kind, l10n),
            active: kind == active,
            onPick: () => controller.setShapeKind(element.id, kind),
          ),
      ],
    );
  }
}

/// One gallery thumbnail: a focusable, keyboard-activatable button drawing the
/// [kind]'s geometry. It carries a localized [label] and `selected`/button
/// semantics (FR-012), highlights when [active] or focused, and runs [onPick]
/// on tap or keyboard activate (Enter/Space).
class _ShapeThumbnail extends StatefulWidget {
  const _ShapeThumbnail({
    required this.kind,
    required this.label,
    required this.active,
    required this.onPick,
  });

  final ShapeKind kind;
  final String label;
  final bool active;
  final VoidCallback onPick;

  @override
  State<_ShapeThumbnail> createState() => _ShapeThumbnailState();
}

class _ShapeThumbnailState extends State<_ShapeThumbnail> {
  static const double _size = 44;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final bool highlighted = widget.active || _focused;
    final Color stroke = widget.active ? colors.primary : colors.foreground;

    return FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPick();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (bool value) => setState(() => _focused = value),
      child: Semantics(
        key: ValueKey<String>('$_p.shape.${widget.kind.name}'),
        button: true,
        enabled: true,
        selected: widget.active,
        label: widget.label,
        onTap: widget.onPick,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPick,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: widget.active ? colors.muted : colors.background,
              border: Border.all(
                color: highlighted ? colors.primary : colors.border,
                width: highlighted ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: CustomPaint(
                painter: _ShapeThumbPainter(kind: widget.kind, color: stroke),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strokes a single shape form into the thumbnail. Line and rectangle draw their
/// dedicated geometry (mirroring the renderer's special cases); every other form
/// is stroked from the shared `shapePath`, so the thumbnail can never diverge
/// from the rendered shape (C7.4).
class _ShapeThumbPainter extends CustomPainter {
  const _ShapeThumbPainter({required this.kind, required this.color});

  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    switch (kind) {
      case ShapeKind.rectangle:
        canvas.drawRect(Offset.zero & size, paint);
      case ShapeKind.line:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      case ShapeKind.ellipse:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.pentagon:
      case ShapeKind.hexagon:
      case ShapeKind.star:
        canvas.drawPath(
          _toUiPath(shapePath(kind,
              JetRect(x: 0, y: 0, width: size.width, height: size.height))),
          paint,
        );
    }
  }

  /// Replays `shapePath` commands into a `dart:ui` [Path] — the same command set
  /// the canvas and PDF painters replay.
  Path _toUiPath(List<PathCommand> commands) {
    final Path path = Path();
    for (final PathCommand c in commands) {
      switch (c) {
        case MoveTo(:final JetOffset to):
          path.moveTo(to.dx, to.dy);
        case LineTo(:final JetOffset to):
          path.lineTo(to.dx, to.dy);
        case ClosePath():
          path.close();
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_ShapeThumbPainter old) =>
      old.kind != kind || old.color != color;
}
