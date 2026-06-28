// Element create / edit / property commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlElementEdit on JetReportDesignerController {
  /// Creates a default element of [type] at the band-relative point [at] within
  /// the band with stable id [bandId], selecting it. The new element gets a fresh
  /// unique id and the per-type default size; its bounds are clamped to the band
  /// (FR-001/002/004/010). An unknown [bandId] is ignored.
  void createElement(
    DesignerToolType type, {
    required String bandId,
    required JetOffset at,
  }) {
    if (findBand(_document.definition, bandId) == null) return;
    final String id = _ids.next(_typeKeyFor(type));
    final JetSize size = kDefaultElementSize[type]!;
    final JetRect bounds =
        JetRect(x: at.dx, y: at.dy, width: size.width, height: size.height);
    _commit(CreateElementCommand(
      bandId: bandId,
      element: buildDefaultElement(type, id, bounds),
    ));
  }

  /// Creates a **data-bound** text element at the band-relative point [at]
  /// within the band with stable id [bandId], bound to [expression] (a
  /// `$F{}`/`$P{}`/`$V{}` string), and selects it (US2 / FR-009, FR-011). Used by
  /// drag-a-field from the Data Source panel. An unknown [bandId] is ignored.
  void createBoundElement({
    required String bandId,
    required JetOffset at,
    required String expression,
  }) {
    if (findBand(_document.definition, bandId) == null) return;
    final String id = _ids.next(_typeKeyFor(DesignerToolType.text));
    final JetSize size = kDefaultElementSize[DesignerToolType.text]!;
    final JetRect bounds =
        JetRect(x: at.dx, y: at.dy, width: size.width, height: size.height);
    _commit(CreateElementCommand(
      bandId: bandId,
      element: TextElement(
        id: id,
        bounds: bounds,
        text: 'Text',
        expression: expression,
      ),
    ));
  }

  // --- Move ------------------------------------------------------------------
  /// Sets any of [id]'s band-relative x/y/width/height numerically (Properties
  /// panel), clamped to its band, as one undoable step (FR-019).
  void setGeometry(String id,
      {double? x, double? y, double? width, double? height}) {
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    final JetRect b = loc.element.bounds;
    final JetRect next = JetRect(
      x: x ?? b.x,
      y: y ?? b.y,
      width: width ?? b.width,
      height: height ?? b.height,
    );
    final JetRect clamped =
        clampToBand(next, loc.band, _document.definition.page);
    if (clamped == b) return;
    _commit(ResizeCommand(id: id, bounds: clamped));
  }

  /// Sets the text of the [TextElement] [id] (inline or Properties), one
  /// undoable step (FR-019). No-op for a non-text or absent id.
  void setText(String id, String text) {
    _commit(SetTextCommand(id: id, text: text));
  }

  /// Sets the display [name] of the element [id] as one undoable step.
  ///
  /// A blank or whitespace-only [name] is normalized to `null` (clearing the
  /// override so the fallback label shows). Renaming to the current value is a
  /// no-op (no history, no notify). Mirrors the report-level [rename].
  void renameElement(String id, String? name) =>
      _commit(RenameElementCommand(id: id, name: _normalizeName(name)));

  /// Binds the [TextElement] [id] to [expression] (a `$F{}`/`$P{}`/`$V{}`
  /// string), as one undoable step (US2 / FR-009). No-op for a non-text or
  /// absent id, or when already bound to the same expression.
  void setBinding(String id, String expression) {
    _commit(SetTextBindingCommand(id: id, expression: expression));
  }

  /// Clears the [TextElement] [id]'s binding, reverting it to its static text
  /// (US2 / FR-012). No-op for a non-text or absent id, or when already static.
  void clearBinding(String id) {
    _commit(SetTextBindingCommand(id: id, expression: null));
  }

  /// Sets the [visible] property of element [id] (undoable). No-op when equal.
  void setElementVisible(String id, BoolProperty visible) =>
      _commit(SetElementVisibleCommand(id: id, visible: visible));

  /// Sets the [TextElement] [id] from the unified value field's [raw] text (013).
  ///
  /// Parses the three forms — a `[field]` simple binding, a `{ … }` template, or
  /// literal text (with `\` escapes) — and applies the result as a single
  /// undoable edit (FR-001/002/003/005). No-op for a non-text or absent id.
  void setValue(String id, String raw) {
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null || loc.element is! TextElement) return;
    final TextElement el = loc.element as TextElement;
    switch (parseValueField(raw)) {
      case LiteralValue(text: final String text):
        _commit(SetValueCommand(id: id, text: text, expression: null));
      case BindingValue(expression: final String expression):
        // Keep the element's literal text as a fallback; the binding drives it.
        _commit(SetValueCommand(id: id, text: el.text, expression: expression));
    }
  }

  /// Sets the [TextElement] [id]'s display [format] (013) — an ICU pattern, or an
  /// empty string to clear it. One undoable step; no-op for a non-text/absent id
  /// or an unchanged format.
  void setFormat(String id, String format) {
    _commit(SetFormatCommand(id: id, format: format.isEmpty ? null : format));
  }

  /// Changes the form of the [ShapeElement] [id] to [kind] as one undoable step
  /// (020 / FR-004), preserving the element's bounds and fill/stroke.
  void setShapeKind(String id, ShapeKind kind) =>
      _commit(SetShapeKindCommand(id: id, kind: kind));

  /// Replaces the [TextElement] [id]'s whole style with [style] as one
  /// undoable step (021 / FR-001…FR-005), preserving its text, bounds,
  /// binding, and format.
  void setTextStyle(String id, JetTextStyle style) =>
      _commit(SetTextStyleCommand(id: id, style: style));

  /// Replaces the [ShapeElement] [id]'s whole style with [style] as one
  /// undoable step (021 / FR-007, FR-008), preserving its kind, bounds, and
  /// flip state.
  void setShapeStyle(String id, JetBoxStyle style) =>
      _commit(SetShapeStyleCommand(id: id, style: style));

  /// Updates one or more properties of the [ChartElement] [id] as one undoable
  /// step, preserving every field not mentioned. A no-op for a non-chart or
  /// absent id.
  void setChartOptions(
    String id, {
    ChartType? chartType,
    String? collectionField,
    String? valueExpression,
    String? categoryExpression,
    String? title,
    bool? showAxes,
    bool? showValueLabels,
    bool? showLegend,
    JetColor? seriesColor,
  }) =>
      _commit(SetChartOptionsCommand(
        id: id,
        chartType: chartType,
        collectionField: collectionField,
        valueExpression: valueExpression,
        categoryExpression: categoryExpression,
        title: title,
        showAxes: showAxes,
        showValueLabels: showValueLabels,
        showLegend: showLegend,
        seriesColor: seriesColor,
      ));

  /// Binds the [ImageElement] [id] to read its picture from the data [field]
  /// (US2 / FR-013). No-op for a non-image or absent id, or when already bound
  /// to the same field.
  void setImageField(String id, String field) {
    _commit(SetImageBindingCommand(id: id, field: field));
  }

  // --- Groups & scopes (first-class entities, spec 024 / FR-015) -------------
}
