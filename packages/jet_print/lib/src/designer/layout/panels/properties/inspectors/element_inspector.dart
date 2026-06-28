// The element inspector: per-element-type property builders
// (text / image / barcode / chart / shape) plus the resolution helpers
// they alone use. Split out of `properties_panel.dart` as an extension so
// it keeps full private access to the panel's state (`setState`, focus
// nodes, `_editingHeader`) without exposing anything or threading callbacks.
part of '../../properties_panel.dart';

extension _ElementInspector on _PropertiesPanelState {
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
      _Header(
        icon: _elementGlyph(element),
        title: elementDisplayLabel(element, l10n),
        rawName: element.name,
        fallback: elementTypeLabel(element, l10n),
        editing: _editingHeader,
        onEditingStart: () => _rebuild(() => _editingHeader = true),
        onEditingEnd: () => _rebuild(() => _editingHeader = false),
        onCommit: (String? name) {
          controller.renameElement(element.id, name);
          _rebuild(() => _editingHeader = false);
        },
        theme: theme,
      ),
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
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesVisible),
      _visibleSection(
        visible: element.visible,
        onChanged: (BoolProperty v) =>
            controller.setElementVisible(element.id, v),
        l10n: l10n,
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
          descendantOperands: _descendantOperands(schema, controller, id),
          descendantFields: _descendantFields(schema, controller, id),
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
      // Barcode inspector (036): symbology picker, data editor (field or
      // literal), toggles (showText / quietZone), ECC level, and color.
      // Each control writes through one controller method → one undo step.
      if (element is BarcodeElement) ...<Widget>[
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>('$_p.barcode.$id'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(l10n.propertiesBarcode),
              // --- Symbology ---------------------------------------------------
              _LabeledRow(
                label: l10n.propertiesSymbology,
                child: ShadSelect<BarcodeSymbology>(
                  selectedOptionBuilder:
                      (BuildContext context, BarcodeSymbology value) => Text(
                          value == BarcodeSymbology.auto
                              ? l10n.barcodeSymbologyAuto
                              : barcodeSymbologyLabel(value)),
                  initialValue: element.symbology,
                  options: <Widget>[
                    for (final BarcodeSymbology s in BarcodeSymbology.values)
                      ShadOption<BarcodeSymbology>(
                        value: s,
                        child: Text(s == BarcodeSymbology.auto
                            ? l10n.barcodeSymbologyAuto
                            : barcodeSymbologyLabel(s)),
                      ),
                  ],
                  onChanged: (BarcodeSymbology? v) {
                    if (v != null) controller.setBarcodeSymbology(id, v);
                  },
                ),
              ),
              // --- Data --------------------------------------------------------
              // One field-or-literal input, like the text Value field: a bare
              // `[field]` token (typed or inserted via the picker) binds to that
              // field; any other text is a literal. The input's contents carry
              // the mode, so there is no separate literal/field switch. No fx
              // affordance — barcode is field-or-literal, not expressions (036).
              _LabeledRow(
                label: l10n.propertiesBarcodeData,
                child: _ValueField(
                  fieldKey: ValueKey<String>('$_p.field.barcodeData.$id'),
                  display: element.dataField != null
                      ? ValueDisplay('[${element.dataField}]')
                      : ValueDisplay(element.data),
                  placeholder: l10n.valueFieldHint,
                  fields: _valueFieldChoices(schema, controller, id),
                  pickerTooltip: l10n.valueFieldPickerTooltip,
                  pickerKeyPrefix: '$_p.field.barcodeData.pick',
                  showFx: false,
                  onCommit: (String v) => controller.setBarcodeValue(id, v),
                ),
              ),
              // Inline hints.
              if (element.dataField != null &&
                  element.dataField!.isNotEmpty &&
                  _unresolved(schema, controller, id,
                      barcodeField: element.dataField))
                _UnresolvedHint(message: l10n.bindingUnresolved),
              // Literal-value validity hint (FR-005/FR-015): a non-empty literal
              // that cannot be encoded for its resolved symbology. A bound
              // field's value is unknown at design time, so no validity hint
              // there — only the unresolved-field hint above.
              if (element.dataField == null &&
                  element.data.isNotEmpty &&
                  _barcodeLiteralInvalid(element))
                _UnresolvedHint(message: l10n.barcodeInvalidValue),
              if (element.symbology == BarcodeSymbology.auto &&
                  element.data.isNotEmpty &&
                  element.dataField == null)
                _InlineNotice(
                  text: l10n.barcodeAutoInferred(
                      resolveConcreteSymbology(element.symbology, element.data)
                          .name),
                  theme: ShadTheme.of(context),
                ),
              // --- Show text (1D only) -----------------------------------------
              if (!isTwoDSymbology(
                  resolveConcreteSymbology(element.symbology, element.data)))
                _LabeledRow(
                  label: l10n.barcodeShowText,
                  child: ShadSwitch(
                    value: element.showText,
                    onChanged: (bool v) => controller.setBarcodeShowText(id, v),
                  ),
                ),
              // --- Quiet zone --------------------------------------------------
              _LabeledRow(
                label: l10n.barcodeQuietZone,
                child: ShadSwitch(
                  value: element.quietZone,
                  onChanged: (bool v) => controller.setBarcodeQuietZone(id, v),
                ),
              ),
              // --- ECC level (QR only) -----------------------------------------
              if (resolveConcreteSymbology(element.symbology, element.data) ==
                  BarcodeSymbology.qrCode)
                _LabeledRow(
                  label: l10n.barcodeEccLevel,
                  child: ShadSelect<QrErrorCorrectionLevel>(
                    selectedOptionBuilder:
                        (BuildContext context, QrErrorCorrectionLevel value) =>
                            Text(value.name.toUpperCase()),
                    initialValue: element.eccLevel,
                    options: <Widget>[
                      for (final QrErrorCorrectionLevel e
                          in QrErrorCorrectionLevel.values)
                        ShadOption<QrErrorCorrectionLevel>(
                          value: e,
                          child: Text(e.name.toUpperCase()),
                        ),
                    ],
                    onChanged: (QrErrorCorrectionLevel? v) {
                      if (v != null) controller.setBarcodeEccLevel(id, v);
                    },
                  ),
                ),
              // --- Color -------------------------------------------------------
              const SizedBox(height: 12),
              _LabeledRow(
                label: l10n.propertiesColor,
                // A compact swatch-only box, left-aligned so it keeps its
                // intrinsic size instead of stretching across the row — matching
                // the text/shape color inputs.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ColorField(
                    keyBase: '$_p.field.barcodeColor',
                    value: element.color,
                    compact: true,
                    onCommit: (JetColor? c) =>
                        controller.setBarcodeColor(id, c!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      // Chart inspector: type picker, binding (collection + expressions), chrome
      // toggles (showAxes / showValueLabels / showLegend), and series color.
      // Each control dispatches one setChartOptions call → one undoable step.
      if (element is ChartElement) ...<Widget>[
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>('$_p.chart.$id'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(l10n.propertiesChart),
              // --- Chart type --------------------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartType,
                child: ShadSelect<ChartType>(
                  selectedOptionBuilder:
                      (BuildContext context, ChartType value) =>
                          _chartTypeItem(value, l10n),
                  initialValue: element.chartType,
                  options: <Widget>[
                    for (final ChartType t in ChartType.values)
                      ShadOption<ChartType>(
                        value: t,
                        child: _chartTypeItem(t, l10n),
                      ),
                  ],
                  onChanged: (ChartType? v) {
                    if (v != null) controller.setChartOptions(id, chartType: v);
                  },
                ),
              ),
              // --- Collection field --------------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartCollection,
                child: _BindingField(
                  fieldKey: ValueKey<String>('$_p.field.chartCollection.$id'),
                  value: element.collectionField,
                  placeholder: l10n.bindingCollectionHint,
                  clearTooltip: l10n.bindingClearTooltip,
                  fields: _chartCollectionChoices(schema, controller, id),
                  pickerTooltip: l10n.bindingFieldPickerTooltip,
                  pickerKeyPrefix: '$_p.field.chartCollection.pick.$id',
                  onSet: (String v) =>
                      controller.setChartOptions(id, collectionField: v),
                  onClear: () =>
                      controller.setChartOptions(id, collectionField: ''),
                ),
              ),
              // --- Value expression --------------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartValue,
                child: _ValueField(
                  fieldKey: ValueKey<String>('$_p.field.chartValue.$id'),
                  display: reverseCompile(element.valueExpression),
                  placeholder: l10n.valueFieldHint,
                  fields: _valueFieldChoices(schema, controller, id),
                  pickerTooltip: l10n.valueFieldPickerTooltip,
                  fxTooltip: l10n.valueFieldFxTooltip,
                  resolvableNames: _resolvableNames(schema, controller, id),
                  descendantOperands:
                      _descendantOperands(schema, controller, id),
                  descendantFields: _descendantFields(schema, controller, id),
                  onCommit: (String v) =>
                      controller.setChartOptions(id, valueExpression: v),
                ),
              ),
              // --- Category expression -----------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartCategory,
                child: _ValueField(
                  fieldKey: ValueKey<String>('$_p.field.chartCategory.$id'),
                  display: element.categoryExpression != null
                      ? reverseCompile(element.categoryExpression!)
                      : const ValueDisplay(''),
                  placeholder: l10n.valueFieldHint,
                  fields: _valueFieldChoices(schema, controller, id),
                  pickerTooltip: l10n.valueFieldPickerTooltip,
                  fxTooltip: l10n.valueFieldFxTooltip,
                  resolvableNames: _resolvableNames(schema, controller, id),
                  descendantOperands:
                      _descendantOperands(schema, controller, id),
                  descendantFields: _descendantFields(schema, controller, id),
                  onCommit: (String v) => controller.setChartOptions(id,
                      categoryExpression: v.isEmpty ? null : v),
                ),
              ),
              // --- Title -------------------------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartTitle,
                child: _TextInput(
                  fieldKey: ValueKey<String>('$_p.field.chartTitle.$id'),
                  value: element.title ?? '',
                  placeholder: l10n.valueFieldHint,
                  onCommit: (String v) => controller.setChartOptions(id,
                      title: v.isEmpty ? null : v),
                ),
              ),
              // --- Chrome toggles ----------------------------------------------
              _LabeledRow(
                label: l10n.propertiesChartShowAxes,
                child: ShadSwitch(
                  value: element.showAxes,
                  onChanged: (bool v) =>
                      controller.setChartOptions(id, showAxes: v),
                ),
              ),
              _LabeledRow(
                label: l10n.propertiesChartShowValueLabels,
                child: ShadSwitch(
                  value: element.showValueLabels,
                  onChanged: (bool v) =>
                      controller.setChartOptions(id, showValueLabels: v),
                ),
              ),
              _LabeledRow(
                label: l10n.propertiesChartShowLegend,
                child: ShadSwitch(
                  value: element.showLegend,
                  onChanged: (bool v) =>
                      controller.setChartOptions(id, showLegend: v),
                ),
              ),
              // --- Series color ------------------------------------------------
              const SizedBox(height: 12),
              _LabeledRow(
                label: l10n.propertiesChartColor,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ColorField(
                    keyBase: '$_p.field.chartColor.$id',
                    value: element.seriesColor,
                    compact: true,
                    onCommit: (JetColor? c) =>
                        controller.setChartOptions(id, seriesColor: c!),
                  ),
                ),
              ),
            ],
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

  /// The localized label for a [ChartType] value.
  String _chartTypeLabel(ChartType type, JetPrintLocalizations l10n) =>
      switch (type) {
        ChartType.bar => l10n.chartTypeBar,
        ChartType.line => l10n.chartTypeLine,
        ChartType.pie => l10n.chartTypePie,
      };

  /// The glyph for a [ChartType] value (vertical bars, line, pie).
  IconData _chartTypeIcon(ChartType type) => switch (type) {
        ChartType.bar => LucideIcons.chartColumn,
        ChartType.line => LucideIcons.chartLine,
        ChartType.pie => LucideIcons.chartPie,
      };

  /// A [ChartType] dropdown entry: its glyph beside its localized label.
  Widget _chartTypeItem(ChartType type, JetPrintLocalizations l10n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_chartTypeIcon(type), size: 16),
          const SizedBox(width: 8),
          Text(_chartTypeLabel(type, l10n)),
        ],
      );

  /// The collection fields available for a chart element to iterate, derived
  /// from the element's band scope. Mirrors the scope-collection picker in the
  /// band inspector but for a chart element rather than a scope node.
  List<FieldDef> _chartCollectionChoices(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
  ) {
    if (schema == null) return const <FieldDef>[];
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return const <FieldDef>[];
    final DetailScope? scope = findScopeOfBand(controller.definition, band.id);
    if (scope == null) return const <FieldDef>[];
    // Walk the scope path up to (but not including) this scope to get
    // the collections available at this scope's parent level.
    final List<DetailScope> chain =
        scopePathToScope(controller.definition, scope.id);
    final List<DetailScope> ancestors =
        chain.length > 1 ? chain.sublist(0, chain.length - 1) : chain;
    return <FieldDef>[
      for (final FieldDef f in fieldsInScopeForChain(schema, ancestors))
        if (f.type == JetFieldType.collection) f,
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
    String? barcodeField,
  }) {
    if (schema == null) return false;
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return false;
    final Set<String> names =
        resolvableNamesForBand(controller.definition, schema, band.id);
    if (expression != null) {
      final Set<String> deep =
          descendantOperandNamesForBand(controller.definition, schema, band.id);
      return !_resolvesAggregateAware(names, deep, expression);
    }
    if (imageField != null) return !names.contains(imageField);
    if (barcodeField != null) return !names.contains(barcodeField);
    return false;
  }

  /// True when [element]'s literal value cannot be encoded for its resolved
  /// symbology (FR-005/FR-015). Drives the design-time validity hint. Only
  /// meaningful for a literal (a bound field's value is unknown at design time).
  bool _barcodeLiteralInvalid(BarcodeElement element) {
    final BarcodeEncodeResult result = const PackageBarcodeEncoder().encode(
      element.symbology,
      element.data,
      width: element.bounds.width,
      height: element.bounds.height,
      showText: element.showText,
      eccLevel: element.eccLevel,
    );
    return result is BarcodeInvalid;
  }

  /// True when every `$F{}` ref in [expression] is in [names], or is an
  /// aggregate operand and a descendant operand (spec 033). Mirrors the fx
  /// editor's statusFor resolution for the inline Unresolved hint.
  bool _resolvesAggregateAware(
      Set<String> names, Set<String> deep, String expression) {
    Set<String> operandRefs;
    try {
      operandRefs = Expression.parse(expression).aggregateOperandFields;
    } on Object {
      operandRefs = const <String>{};
    }
    for (final String ref in fieldRefsIn(expression)) {
      if (names.contains(ref)) continue;
      if (operandRefs.contains(ref) && deep.contains(ref)) continue;
      return false;
    }
    return true;
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

  /// Descendant leaf names valid as aggregate operands for [elementId]'s band
  /// (spec 033): leaves of nested collections below the band's scope. Empty
  /// when no schema/band, so behavior is unchanged where no source is attached.
  Set<String> _descendantOperands(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
  ) {
    if (schema == null) return const <String>{};
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return const <String>{};
    return descendantOperandNamesForBand(
        controller.definition, schema, band.id);
  }

  /// The fx-palette choices for [elementId]'s descendant operands — one
  /// [FieldDef] per descendant leaf, rendered marked as a deeper field. Empty
  /// when no schema/band.
  List<FieldDef> _descendantFields(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    String elementId,
  ) {
    if (schema == null) return const <FieldDef>[];
    final Band? band = findBandOfElement(controller.definition, elementId);
    if (band == null) return const <FieldDef>[];
    return descendantFieldChoicesForBand(
        controller.definition, schema, band.id);
  }

  // --- Band ------------------------------------------------------------------
  // A band inspector edits only what belongs to the band itself: its height.
  // The group's key + pagination flags live in the Group inspector, and a
  // scope's collection in the Scope inspector — so a flag is never shown on both
  // a group header and footer band (the 023 two-bands smell, fixed by spec 024).
}
