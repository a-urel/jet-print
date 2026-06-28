import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/band.dart';
import '../../../domain/bool_property.dart';
import '../../../domain/column_layout.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/chart_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/group_level.dart';
import '../../../domain/page_format.dart';
import '../../../domain/report_band.dart' show BandType;
import '../../../domain/report_definition.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../../domain/watermark.dart';
import '../../../expression/expression.dart';
import '../../../rendering/elements/barcode/barcode_encoder.dart';
import '../../../rendering/elements/barcode/package_barcode_encoder.dart';
import '../../../rendering/elements/barcode/symbology_inference.dart';
import '../../../rendering/elements/shape_path.dart';
import '../../../rendering/frame/primitive.dart';
import '../../../rendering/text/font_registry.dart';
import '../../../rendering/text/ui_font_family.dart';
import '../../canvas/paper_palette.dart';
import '../../controller/band_walker.dart';
import '../../controller/binding_resolution.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../designer_font_scope.dart';
import '../../designer_schema_scope.dart';
import '../../designer_scope.dart';
import '../../field_type_glyph.dart';
import '../../format_presets.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/element_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../../l10n/object_display_label.dart';
import '../../margin_presets.dart';
import '../../paper_presets.dart';
import '../../template/value_template_compiler.dart';
import '../region_chrome.dart';
import '../widgets/editable_label.dart';
import 'barcode_symbology_label.dart';
import 'expression_editor_dialog.dart';

part 'style_editors.dart';
part 'properties/fields/layout_bits.dart';
part 'properties/fields/text_input.dart';
part 'properties/fields/pickers.dart';
part 'properties/fields/value_field.dart';
part 'properties/fields/previews.dart';
part 'properties/fields/shape_gallery.dart';
part 'properties/inspectors/element_inspector.dart';

/// Stable test-seam key prefix for the inspector's fields and empty state.
const String _p = 'jet_print.designer.properties';

/// One friendly, localized column-layout diagnostic for display.
typedef _ColumnDiagnostic = ({bool isError, String message});

/// Friendly, localized column-layout diagnostics for the active label band
/// (spec 035 UX). Derived from the SAME geometry the engine's `validate()`
/// checks (`_validateColumns`) — the conditions and the bodyWidth/bodyCapacity
/// formulas mirror it exactly — but presented in plain language, localized, and
/// **de-duplicated**: one row for ALL clipped elements rather than the engine's
/// one-developer-string-per-element. The engine's raw strings are no longer
/// surfaced here.
List<_ColumnDiagnostic> _columnDiagnostics(ReportDefinition def, Band band,
    ColumnLayout cl, JetPrintLocalizations l10n) {
  final List<_ColumnDiagnostic> out = <_ColumnDiagnostic>[];
  if (cl.columnCount < 1) {
    out.add((isError: true, message: l10n.propertiesColumnErrTooFew));
  }
  if (cl.columnWidth <= 0 || cl.columnSpacing < 0 || cl.rowSpacing < 0) {
    out.add((isError: true, message: l10n.propertiesColumnErrDimensions));
  }
  final PageFormat page = def.page;
  final double bodyWidth = page.width - page.margins.left - page.margins.right;
  if (cl.columnCount >= 1 && cl.columnWidth > 0) {
    final double grid = cl.columnCount * cl.columnWidth +
        (cl.columnCount - 1) * cl.columnSpacing;
    if (grid > bodyWidth) {
      out.add((isError: true, message: l10n.propertiesColumnErrGridTooWide));
    }
  }
  final double headerH = def.furniture.pageHeader?.height ?? 0;
  final double footerH = def.furniture.pageFooter?.height ?? 0;
  final double bodyCapacity =
      page.height - page.margins.top - page.margins.bottom - headerH - footerH;
  if (band.height > bodyCapacity) {
    out.add((isError: true, message: l10n.propertiesColumnErrLabelTooTall));
  }
  final int clipped = band.elements
      .where((ReportElement e) => e.bounds.x + e.bounds.width > cl.columnWidth)
      .length;
  if (clipped > 0) {
    out.add((
      isError: false,
      message: l10n.propertiesColumnElementsClipped(clipped)
    ));
  }
  return out;
}

/// The [layout] with [count] columns, refitting `columnWidth` so the grid fills
/// the page body exactly (spec 035 UX: changing the column count always refits
/// the width, so adding a column never overflows the page). A `count < 1` —
/// which the validator flags — commits as-is, guarding the divide-by-zero.
ColumnLayout _withColumnCount(
    JetReportDesignerController controller, ColumnLayout layout, int count) {
  if (count < 1) return layout.copyWith(columnCount: count);
  final PageFormat page = controller.definition.page;
  final double bodyWidth = page.width - page.margins.left - page.margins.right;
  final double width = (bodyWidth - (count - 1) * layout.columnSpacing) / count;
  return layout.copyWith(columnCount: count, columnWidth: width);
}

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

  /// Whether the Properties header is in inline-edit mode (rename in progress).
  bool _editingHeader = false;

  /// The key of the object whose header was last rendered — used to detect a
  /// selection change and reset [_editingHeader] automatically.
  String? _lastInspectedKey;

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

  /// Proxy for [setState] callable from the panel's `part` extensions: the
  /// analyzer flags `setState` as a protected member when reached through an
  /// extension (it is not an instance member of the State subclass), so the
  /// inspector extensions rebuild through this wrapper instead.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final JetDataSchema? schema = DesignerSchemaScope.of(context);
    final selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    _schedulePendingFocus(controller);

    // Compute the key for the currently-inspected object.  When it changes
    // (different element, band, or a selection clear) reset the header editing
    // flag so the inline rename field never persists into a new selection.
    final String? inspectedKey = selection.bandId ??
        selection.groupId ??
        selection.scopeId ??
        selection.singleOrNull;
    if (inspectedKey != _lastInspectedKey) {
      _lastInspectedKey = inspectedKey;
      if (_editingHeader) _editingHeader = false;
    }

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
        title: bandDisplayLabel(band, l10n),
        rawName: band.name,
        fallback: bandTypeLabel(band.type, l10n),
        editing: _editingHeader,
        onEditingStart: () => setState(() => _editingHeader = true),
        onEditingEnd: () => setState(() => _editingHeader = false),
        onCommit: (String? name) {
          controller.renameBand(band.id, name);
          setState(() => _editingHeader = false);
        },
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
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesVisible),
      _visibleSection(
        visible: band.visible,
        onChanged: (BoolProperty v) => controller.setBandVisible(band.id, v),
        l10n: l10n,
      ),
    ];
    if (band.type == BandType.detail) {
      children
        ..add(const SizedBox(height: 18))
        ..addAll(_bandListSection(controller, bandId, theme, l10n, schema))
        ..addAll(_columnLayoutSection(controller, bandId, theme, l10n));
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
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.groupName'),
        value: group.name,
        placeholder: l10n.propertiesGroupName,
        onCommit: (String v) => controller.setGroupName(groupId, v),
      ),
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesGroupKey),
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
        Text(l10n.propertiesListRootSource, style: theme.textTheme.muted),
      ];
    }
    return <Widget>[
      SectionLabel(l10n.propertiesList),
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

  /// The label-grid (multi-column) editor for a detail band (spec 035). Shown
  /// only for detail bands. Three states: no layout + eligible body → an
  /// enabled "Add column layout"; no layout + ineligible → the Add disabled with
  /// a tooltip; layout present → the four geometry fields + Remove (editable
  /// even when ineligible, so an orphaned layout stays fixable). Validation rows
  /// and the inactive notice are appended by Task 3.
  List<Widget> _columnLayoutSection(
    JetReportDesignerController controller,
    String bandId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final ReportDefinition def = controller.definition;
    final Band? band = findBand(def, bandId);
    if (band == null || band.type != BandType.detail) return const <Widget>[];
    final ColumnLayout? layout = band.columnLayout;
    final bool eligible =
        def.isPureSingleDetailBody && def.soleDetailBand?.id == bandId;

    final List<Widget> out = <Widget>[const SizedBox(height: 18)];

    // No layout yet: the "Add column layout" button is self-describing, so a
    // section header would be redundant — show the button alone.
    if (layout == null) {
      out.add(_ColumnLayoutAddButton(
        enabled: eligible,
        label: l10n.propertiesColumnLayoutAdd,
        disabledTooltip: l10n.propertiesColumnLayoutAddDisabled,
        onAdd: () {
          final double bodyWidth =
              def.page.width - def.page.margins.left - def.page.margins.right;
          controller.setColumnLayout(
            bandId,
            ColumnLayout(
              columnCount: 2,
              columnWidth: bodyWidth / 2,
              columnSpacing: 0,
              rowSpacing: 0,
            ),
          );
        },
      ));
      return out;
    }

    // A layout exists: head the editor with the section title.
    out
      ..add(_Header(
        icon: LucideIcons.columns3,
        title: l10n.propertiesColumnLayout,
        theme: theme,
      ))
      ..add(const SizedBox(height: 14));

    out
      ..add(_LabeledRow(
        label: l10n.propertiesColumnCount,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnCount'),
          prefix: LucideIcons.columns3,
          value: layout.columnCount.toDouble(),
          onCommit: (double v) => controller.setColumnLayout(
              bandId, _withColumnCount(controller, layout, v.round())),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesColumnWidth,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnWidth'),
          prefix: LucideIcons.moveHorizontal,
          value: layout.columnWidth,
          onCommit: (double v) => controller.setColumnLayout(
              bandId, layout.copyWith(columnWidth: v)),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesColumnSpacing,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnSpacing'),
          prefix: LucideIcons.moveHorizontal,
          value: layout.columnSpacing,
          onCommit: (double v) => controller.setColumnLayout(
              bandId, layout.copyWith(columnSpacing: v)),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesRowSpacing,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.rowSpacing'),
          prefix: LucideIcons.moveVertical,
          value: layout.rowSpacing,
          onCommit: (double v) => controller.setColumnLayout(
              bandId, layout.copyWith(rowSpacing: v)),
        ),
      ))
      ..add(const SizedBox(height: 8))
      ..add(_ColumnLayoutRemoveButton(
        label: l10n.propertiesColumnLayoutRemove,
        onRemove: () => controller.removeColumnLayout(bandId),
      ));

    // When the report shape no longer activates the grid, the geometry checks
    // are moot — show only the inactive notice (FR-009). Otherwise surface the
    // friendly, localized column diagnostics (spec 035 UX): derived from the
    // same geometry the engine validates, but rounded, plain-language, and with
    // the per-element overflows collapsed into one row.
    if (!eligible) {
      out
        ..add(const SizedBox(height: 8))
        ..add(_InlineNotice(
            text: l10n.propertiesColumnLayoutInactive, theme: theme));
    } else {
      for (final _ColumnDiagnostic d
          in _columnDiagnostics(def, band, layout, l10n)) {
        out.add(const SizedBox(height: 6));
        out.add(d.isError
            ? _UnresolvedHint(message: d.message)
            : _InlineWarning(text: d.message, theme: theme));
      }
    }
    return out;
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
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.reportName'),
        value: controller.definition.name,
        placeholder: l10n.reportNameHint,
        onCommit: controller.rename,
      ),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesPage),
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
      ..._watermarkSection(controller, theme, l10n),
    ];
  }

  /// The report-level watermark editors (text watermark authoring). Shown in the
  /// report-root inspector when the report root is selected. The enable toggle
  /// creates a large-font default so the watermark is visible immediately; an
  /// image watermark (no UI to author bytes) is shown read-only with opacity/angle
  /// still editable.
  List<Widget> _watermarkSection(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final Watermark? wm = controller.definition.furniture.watermark;
    final List<Widget> out = <Widget>[
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesWatermark),
      ShadSwitch(
        key: const ValueKey<String>('$_p.field.watermarkEnable'),
        value: wm != null,
        onChanged: (bool on) => controller.setWatermark(
          on
              ? Watermark(
                  text: l10n.watermarkDefaultText,
                  textStyle: const JetTextStyle(fontSize: 64))
              : null,
        ),
        label: Text(l10n.watermarkEnable),
      ),
    ];
    if (wm == null) return out;

    final bool isImage = wm.imageBytes != null && wm.text == null;
    if (isImage) {
      out
        ..add(const SizedBox(height: 10))
        ..add(Text(
          l10n.watermarkImageExternal,
          style: theme.textTheme.muted
              .copyWith(color: theme.colorScheme.mutedForeground),
        ))
        ..add(const SizedBox(height: 10))
        ..add(_watermarkOpacity(controller, wm))
        ..add(const SizedBox(height: 8))
        ..add(_watermarkAngle(controller, wm));
      return out;
    }

    out
      ..add(const SizedBox(height: 10))
      ..add(SectionLabel(l10n.watermarkText))
      // Text + a small inline colour swatch share one row; the compact picker
      // mirrors the element font-colour control.
      ..add(Row(
        children: <Widget>[
          Expanded(
            child: _TextInput(
              fieldKey: const ValueKey<String>('$_p.field.watermarkText'),
              value: wm.text ?? '',
              placeholder: l10n.watermarkDefaultText,
              onCommit: (String v) =>
                  controller.setWatermark(wm.copyWith(text: v)),
            ),
          ),
          const SizedBox(width: 8),
          _ColorField(
            keyBase: '$_p.field.watermarkColor',
            value: wm.textStyle.color,
            compact: true,
            onCommit: (JetColor? c) => controller.setWatermark(
              wm.copyWith(
                textStyle: wm.textStyle.copyWith(color: c ?? JetColor.black),
              ),
            ),
          ),
        ],
      ))
      ..add(const SizedBox(height: 8))
      // Font size, opacity, angle in one row; each field's prefix icon
      // (type / droplet / rotate) stands in for the dropped label.
      ..add(Row(
        children: <Widget>[
          Expanded(
            child: _NumberField(
              fieldKey: const ValueKey<String>('$_p.field.watermarkFontSize'),
              prefix: LucideIcons.type,
              value: wm.textStyle.fontSize,
              onCommit: (double v) => controller.setWatermark(
                wm.copyWith(textStyle: wm.textStyle.copyWith(fontSize: v)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _watermarkOpacity(controller, wm)),
          const SizedBox(width: 8),
          Expanded(child: _watermarkAngle(controller, wm)),
        ],
      ));
    return out;
  }

  Widget _watermarkOpacity(
    JetReportDesignerController controller,
    Watermark wm,
  ) =>
      _NumberField(
        fieldKey: const ValueKey<String>('$_p.field.watermarkOpacity'),
        prefix: LucideIcons.droplet,
        value: wm.opacity,
        step: 0.1,
        onCommit: (double v) =>
            controller.setWatermark(wm.copyWith(opacity: v)),
      );

  Widget _watermarkAngle(
    JetReportDesignerController controller,
    Watermark wm,
  ) =>
      _NumberField(
        fieldKey: const ValueKey<String>('$_p.field.watermarkAngle'),
        prefix: LucideIcons.rotateCw,
        value: wm.angleDegrees,
        onCommit: (double v) =>
            controller.setWatermark(wm.copyWith(angleDegrees: v)),
      );

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

  /// The Visible toggle + optional expression control, shared by the element
  /// inspector and [_bandInspector].  [l10n] is the caller's resolved
  /// localizations instance.
  Widget _visibleSection({
    required BoolProperty visible,
    required ValueChanged<BoolProperty> onChanged,
    required JetPrintLocalizations l10n,
  }) =>
      _VisibleField(
        visible: visible,
        onChanged: onChanged,
        fxTooltip: l10n.propertiesVisibleWhen,
        clearTooltip: l10n.propertiesVisibleClear,
      );
}

IconData _elementGlyph(ReportElement element) {
  if (element is TextElement) return LucideIcons.type;
  if (element is ShapeElement) return LucideIcons.square;
  if (element is ImageElement) return LucideIcons.image;
  if (element is BarcodeElement) return LucideIcons.barcode;
  if (element is ChartElement) return LucideIcons.chartBar;
  return LucideIcons.square;
}
