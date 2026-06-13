/// The public edit-state seam for the report designer.
library;

import 'package:flutter/foundation.dart';

import '../../domain/elements/shape_element.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_template.dart';
import '../../domain/styles/text_style.dart';
import '../canvas/design_tunables.dart';
import '../canvas/resize_handle.dart';
import '../template/value_template_compiler.dart';
import 'bulk_geometry.dart';
import 'clipboard.dart';
import 'commands/clipboard_command.dart';
import 'commands/create_element_command.dart';
import 'commands/delete_command.dart';
import 'commands/move_command.dart';
import 'commands/reorder_command.dart';
import 'commands/resize_command.dart';
import 'commands/set_band_collection_command.dart';
import 'commands/set_band_height_command.dart';
import 'commands/set_binding_command.dart';
import 'commands/set_format_command.dart';
import 'commands/set_page_format_command.dart';
import 'commands/set_shape_kind_command.dart';
import 'commands/set_template_name_command.dart';
import 'commands/set_text_command.dart';
import 'commands/set_text_style_command.dart';
import 'commands/set_value_command.dart';
import 'default_template.dart';
import 'designer_document.dart';
import 'edit_command.dart';
import 'edit_history.dart';
import 'element_bounds.dart';
import 'element_clone.dart';
import 'element_id_factory.dart';
import 'page_format_clamp.dart';
import 'selection.dart';
import 'snapping.dart';

/// Owns the editable design and all editing operations for [JetReportDesigner].
///
/// A [ChangeNotifier] holding the current [template], the [selection], and an
/// unbounded session undo/redo history of immutable `(template, selection)`
/// snapshots ([DesignerDocument]). Every state-changing edit funnels through a
/// single [EditCommand] commit path, so:
///
/// * undo/redo restore **both** model and selection exactly (FR-017), and
/// * each operation is a pure, independently-testable transform.
///
/// The controller is headless — it performs no filesystem or platform I/O; a
/// host drives save/open via `JetReportFormat` and the designer's
/// `onSaveRequested`/`onOpenRequested` hooks (FR-022).
///
/// Property editing this iteration is geometry + text only; the full per-type
/// property suite is deferred (contracts §6).
class JetReportDesignerController extends ChangeNotifier {
  /// Creates a controller over [template], or a blank default design when none
  /// is supplied (so `JetReportDesignerController()` is drop-in).
  JetReportDesignerController({ReportTemplate? template})
      : _document = DesignerDocument(
          template: template ?? defaultBlankTemplate(),
          selection: Selection.empty,
        ) {
    _ids.seedFrom(_document.template);
  }

  DesignerDocument _document;
  final EditHistory _history = EditHistory();
  final ElementIdFactory _ids = ElementIdFactory();

  /// The current report model — the value a host saves (FR-022).
  ReportTemplate get template => _document.template;

  /// The currently-selected element ids.
  Selection get selection => _document.selection;

  /// Whether an [undo] is available (drives top-bar enablement, US3.4).
  bool get canUndo => _history.canUndo;

  /// Whether a [redo] is available (drives top-bar enablement, US3.4).
  bool get canRedo => _history.canRedo;

  /// Whether the current selection can be cut, copied, duplicated or deleted —
  /// true iff one or more elements are selected (a band/report selection holds
  /// no element ids). Both clipboard UI surfaces gate Cut/Copy/Duplicate/Delete
  /// on this single predicate so they cannot diverge (016 / FR-004, FR-005a,
  /// FR-012).
  bool get canCopy => _document.selection.ids.isNotEmpty;

  /// Whether there is clipboard content to paste — true once the session's first
  /// [copy] or [cut] has filled the in-memory clipboard, and true thereafter
  /// (the clipboard never re-empties). Gates Paste on both UI surfaces (016 /
  /// FR-005, FR-012).
  bool get canPaste => !_clipboard.isEmpty;

  /// A monotonically increasing model-revision counter; the canvas painter uses
  /// it to decide when to rebuild its cached frame (D5).
  int get revision => _history.revision;

  /// Bumped on every live drag-preview change (move/resize/band-resize update,
  /// commit, and cancel), so [frameVersion] ticks while the committed [revision]
  /// stays put — the canvas re-records its cached picture from [displayTemplate]
  /// in realtime during a drag, without a single mid-drag history entry.
  int _frameSerial = 0;

  /// The version of the *displayed* frame: it changes on any committed edit (via
  /// [revision]) **and** on any live drag-preview change (via [_frameSerial]), so
  /// the canvas re-records its cached picture whenever what should be on screen
  /// changes — including mid-drag, when [revision] alone would not move.
  int get frameVersion => revision + _frameSerial;

  /// The template the canvas should paint: the committed [template], or — while a
  /// move, element-resize, or band-resize drag is in progress — that template
  /// with the live drag baked in, so the design follows the pointer in realtime
  /// instead of snapping into place on mouse-up. The committed model is untouched
  /// until commit (one undo step per drag); this is a pure, throwaway projection
  /// rebuilt from the same [MoveCommand] / [ResizeCommand] / [SetBandHeightCommand]
  /// that commit uses, so the live frame and the committed frame are
  /// pixel-identical for the same geometry.
  ///
  /// A band resize reflows every band below it, so the canvas must lay out its
  /// chrome (separators, grid, badges) from *this* template — not the committed
  /// one — to keep the chrome in step with the live picture (see the canvas's
  /// display-vs-committed layout split).
  ReportTemplate get displayTemplate {
    final JetOffset? move = _moveDelta;
    if (move != null && (move.dx != 0 || move.dy != 0)) {
      final Map<String, JetRect> targets = _clampedMoveTargets(move);
      if (targets.isNotEmpty) {
        return MoveCommand(targets).apply(_document).template;
      }
    }
    final String? rid = _resizeId;
    final JetRect? preview = _resizePreview;
    if (rid != null && preview != null) {
      return ResizeCommand(id: rid, bounds: preview).apply(_document).template;
    }
    final int? bIndex = _bandResizeIndex;
    final double? height = _bandResizePreviewHeight;
    if (bIndex != null && height != null) {
      return SetBandHeightCommand(bandIndex: bIndex, height: height)
          .apply(_document)
          .template;
    }
    return _document.template;
  }

  /// Replaces the whole design with [template], clearing history and re-seeding
  /// id assignment past the largest existing suffix (FR-004).
  void open(ReportTemplate template) {
    _pendingPropertiesFocus = false; // stale intent from the prior document
    _document =
        DesignerDocument(template: template, selection: Selection.empty);
    _history.clear();
    _ids.seedFrom(template);
    notifyListeners();
  }

  // --- Selection -------------------------------------------------------------
  // Selection changes are not history entries, but because every snapshot
  // includes the selection, undoing a model edit still restores the prior
  // selection (FR-017).

  /// Selects exactly [id] (replacing any prior selection).
  void select(String id) => _setSelection(Selection.of(<String>[id]));

  /// Selects the band at [index] (replacing any prior selection). The band
  /// becomes the selection target — exclusive with element/report selection. An
  /// out-of-range [index] is ignored.
  void selectBand(int index) {
    if (index < 0 || index >= _document.template.bands.length) return;
    _setSelection(Selection.band(index));
  }

  /// Selects the report/page itself (replacing any prior selection).
  void selectReport() => _setSelection(Selection.report());

  /// Clears the selection.
  void clearSelection() => _setSelection(Selection.empty);

  void _setSelection(Selection selection) {
    if (selection == _document.selection) return;
    _document = _document.withSelection(selection);
    notifyListeners();
  }

  // --- Properties-focus intent -----------------------------------------------
  // An ephemeral UI signal, not model state: never serialized, never a history
  // entry, untouched by undo/redo; cleared by [open] (a request must not outlive its document).

  bool _pendingPropertiesFocus = false;

  /// Whether a [requestPropertiesFocus] is awaiting consumption. Long-lived
  /// designer chrome (the shell, the right panel) peeks at this to bring the
  /// Properties inspector forward without claiming the event.
  bool get pendingPropertiesFocus => _pendingPropertiesFocus;

  /// Asks the designer chrome to bring the Properties inspector forward and
  /// move keyboard focus into the selected element's most relevant field (the
  /// canvas calls this on a double-tap). The inspector consumes the request
  /// via [takePropertiesFocus].
  void requestPropertiesFocus() {
    _pendingPropertiesFocus = true;
    notifyListeners();
  }

  /// Consumes a pending Properties-focus request: returns whether one was
  /// pending and clears it. Called once per request by the Properties
  /// inspector after it moves keyboard focus. Does not notify.
  bool takePropertiesFocus() {
    final bool pending = _pendingPropertiesFocus;
    _pendingPropertiesFocus = false;
    return pending;
  }

  // --- Creation --------------------------------------------------------------

  /// Creates a default element of [type] at the band-relative point [at] within
  /// the band at [bandIndex], selecting it. The new element gets a fresh unique
  /// id and the per-type default size; its bounds are clamped to the band
  /// (FR-001/002/004/010). An out-of-range [bandIndex] is ignored.
  void createElement(
    DesignerToolType type, {
    required int bandIndex,
    required JetOffset at,
  }) {
    if (bandIndex < 0 || bandIndex >= _document.template.bands.length) return;
    final String id = _ids.next(_typeKeyFor(type));
    final JetSize size = kDefaultElementSize[type]!;
    final JetRect bounds =
        JetRect(x: at.dx, y: at.dy, width: size.width, height: size.height);
    _commit(CreateElementCommand(
      bandIndex: bandIndex,
      element: buildDefaultElement(type, id, bounds),
    ));
  }

  /// Creates a **data-bound** text element at the band-relative point [at]
  /// within the band at [bandIndex], bound to [expression] (a `$F{}`/`$P{}`/
  /// `$V{}` string), and selects it (US2 / FR-009, FR-011). Used by drag-a-field
  /// from the Data Source panel. The new element gets a fresh id and the default
  /// text size; its literal text is a neutral fallback shown only if the binding
  /// is later cleared. An out-of-range [bandIndex] is ignored.
  void createBoundElement({
    required int bandIndex,
    required JetOffset at,
    required String expression,
  }) {
    if (bandIndex < 0 || bandIndex >= _document.template.bands.length) return;
    final String id = _ids.next(_typeKeyFor(DesignerToolType.text));
    final JetSize size = kDefaultElementSize[DesignerToolType.text]!;
    final JetRect bounds =
        JetRect(x: at.dx, y: at.dy, width: size.width, height: size.height);
    _commit(CreateElementCommand(
      bandIndex: bandIndex,
      element: TextElement(
        id: id,
        bounds: bounds,
        text: 'Text',
        expression: expression,
      ),
    ));
  }

  // --- Move ------------------------------------------------------------------

  /// Translates every selected element by [delta] points (band-relative),
  /// clamping each to its band ∩ page, as one undoable step (FR-008/010/017).
  /// No-op when nothing is selected or the delta is zero.
  void moveBy(JetOffset delta) {
    if (delta.dx == 0 && delta.dy == 0) return;
    final Map<String, JetRect> targets = _clampedMoveTargets(delta);
    if (targets.isEmpty) return;
    _commit(MoveCommand(targets));
  }

  JetOffset? _moveDelta;
  List<SnapGuide> _guides = const <SnapGuide>[];
  int? _activeBand;

  /// The live drag delta during a move interaction (points), or null when no
  /// move is in progress. The selection overlay reads this to draw drag ghosts
  /// without touching the committed model (so the cached frame is not rebuilt
  /// mid-drag).
  JetOffset? get moveDelta => _moveDelta;

  /// Guides (band-relative) currently firing during a live move/resize, for the
  /// overlay to draw (FR-023 / SC-004). Empty when no guide is active.
  List<SnapGuide> get activeGuides => _guides;

  /// The band index of the element being moved/resized, so the overlay can map
  /// band-relative guide positions to page coordinates. Null when idle.
  int? get activeBand => _activeBand;

  /// Begins a live move of the current selection (no history yet).
  void beginMove() => _moveDelta = const JetOffset(0, 0);

  /// Updates the in-progress move to a cumulative [delta] (points). When a
  /// single element is selected and snapping is on, [threshold] (points) and the
  /// grid/sibling/band candidates pull the delta to an aligned position and
  /// publish guides. [bypassSnap] (Alt/Option) disables snapping for this update.
  void updateMove(JetOffset delta,
      {double threshold = 0, bool bypassSnap = false}) {
    JetOffset effective = delta;
    _guides = const <SnapGuide>[];
    _activeBand = null;
    final String? single = _document.selection.singleOrNull;
    if (single != null && _snapEnabled && !bypassSnap && threshold > 0) {
      final ({int bandIndex, ReportElement element})? loc = _locate(single);
      if (loc != null) {
        final JetRect b = loc.element.bounds;
        final SnapResult result = snapMove(
          JetRect(
              x: b.x + delta.dx,
              y: b.y + delta.dy,
              width: b.width,
              height: b.height),
          siblings: _siblingBounds(loc.bandIndex, single),
          bandBox: _bandBox(loc.bandIndex),
          // Grid snapping is governed solely by the snap tool now (D3): we are
          // already inside the `_snapEnabled` guard, so feed the grid candidates
          // unconditionally. `_gridEnabled` controls only the grid's VISIBILITY.
          grid: true,
          gridStep: kGridStep,
          threshold: threshold,
        );
        effective = JetOffset(result.rect.x - b.x, result.rect.y - b.y);
        _guides = result.guides;
        _activeBand = loc.bandIndex;
      }
    }
    _moveDelta = effective;
    _frameSerial++;
    notifyListeners();
  }

  /// Commits the in-progress move as a single history entry (FR-017), or clears
  /// the transient state when nothing moved.
  void commitMove() {
    final JetOffset? delta = _moveDelta;
    _moveDelta = null;
    _guides = const <SnapGuide>[];
    _activeBand = null;
    _frameSerial++; // the drag's preview frame is gone; re-record the committed one
    bool committed = false;
    if (delta != null && (delta.dx != 0 || delta.dy != 0)) {
      final Map<String, JetRect> targets = _clampedMoveTargets(delta);
      if (targets.isNotEmpty) committed = _commit(MoveCommand(targets));
    }
    // Always repaint to drop the drag ghost + snap guides — even when the move
    // was wholly absorbed by clamping (which commits nothing), so the guide
    // never stays frozen on the canvas with no drag in progress.
    if (!committed) notifyListeners();
  }

  /// Discards an in-progress move, restoring the pre-drag view.
  void cancelMove() {
    if (_moveDelta == null) return;
    _moveDelta = null;
    _guides = const <SnapGuide>[];
    _activeBand = null;
    _frameSerial++;
    notifyListeners();
  }

  // --- Resize ----------------------------------------------------------------

  bool _gridEnabled = true;
  bool _snapEnabled = false;
  bool _rulersEnabled = true;
  String? _resizeId;
  ResizeHandle? _resizeHandle;
  JetRect? _resizeStart;
  JetRect? _resizePreview;

  /// Whether the alignment grid is **drawn** on the canvas (top-bar toggle;
  /// default on, FR-014). Visibility only — since 015 this no longer gates
  /// snapping (the magnet does). All four grid/snap combinations are valid, and
  /// elements snap to the grid even when it is hidden (FR-010). Never serialized.
  bool get gridEnabled => _gridEnabled;

  /// Whether snapping is active — the **sole** gate for all snapping (grid +
  /// sibling + band) during move/resize (default **off**; the magnet must be
  /// switched on to snap, FR-008/FR-010).
  bool get snapEnabled => _snapEnabled;

  /// Shows or hides the alignment grid (visibility only; does not affect
  /// snapping). A no-op when [value] already matches.
  void setGridEnabled(bool value) {
    if (_gridEnabled == value) return;
    _gridEnabled = value;
    notifyListeners();
  }

  /// Toggles all snapping (grid + sibling + band).
  void setSnapEnabled(bool value) {
    if (_snapEnabled == value) return;
    _snapEnabled = value;
    notifyListeners();
  }

  /// Whether the measurement rulers are shown along the canvas's top and left
  /// edges (top-bar toggle; default on, FR-017). A per-session view preference —
  /// like [gridEnabled]/[snapEnabled], it is never serialized into the report.
  /// The canvas reads it to inset its viewport and draw the strips; the top bar
  /// reads it for the ruler toggle's active state.
  bool get rulersEnabled => _rulersEnabled;

  /// Shows or hides the rulers. A no-op when [value] already matches (so the
  /// toggle never churns listeners); otherwise notifies.
  void setRulersEnabled(bool value) {
    if (_rulersEnabled == value) return;
    _rulersEnabled = value;
    notifyListeners();
  }

  /// The previewed band-relative bounds of [id] during a live resize, or null.
  /// The overlay draws the selection at this preview while dragging a handle.
  JetRect? previewBoundsFor(String id) =>
      _resizeId == id ? _resizePreview : null;

  /// Begins resizing element [id] by dragging [handle].
  void beginResize(String id, ResizeHandle handle) {
    final ({int bandIndex, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    _resizeId = id;
    _resizeHandle = handle;
    _resizeStart = loc.element.bounds;
    _resizePreview = loc.element.bounds;
    _activeBand = loc.bandIndex;
    _guides = const <SnapGuide>[];
  }

  /// Updates the in-progress resize by a cumulative pointer [delta] (points),
  /// applying the min-size floor, optional snapping (within [threshold] points,
  /// [bypassSnap] to disable), and band clamping; publishes the preview + guides.
  void updateResize(JetOffset delta,
      {double threshold = 0, bool bypassSnap = false}) {
    final String? id = _resizeId;
    final ResizeHandle? handle = _resizeHandle;
    final JetRect? start = _resizeStart;
    if (id == null || handle == null || start == null) return;
    final ({int bandIndex, ReportElement element})? loc = _locate(id);
    if (loc == null) return;

    final bool isLine = loc.element is ShapeElement &&
        (loc.element as ShapeElement).kind == ShapeKind.line;
    final double minW = isLine ? 0 : kMinElementSize;
    final double minH = isLine ? 0 : kMinElementSize;

    JetRect resized =
        resizeRect(start, handle, delta, minWidth: minW, minHeight: minH);
    if (_snapEnabled && !bypassSnap && threshold > 0) {
      final SnapResult result = snapResize(
        resized,
        handle,
        siblings: _siblingBounds(loc.bandIndex, id),
        bandBox: _bandBox(loc.bandIndex),
        // Decoupled (D3): grid snapping follows the snap tool only — we are
        // inside the `_snapEnabled` guard — while `_gridEnabled` is visibility.
        grid: true,
        gridStep: kGridStep,
        threshold: threshold,
      );
      resized = result.rect;
      _guides = result.guides;
    } else {
      _guides = const <SnapGuide>[];
    }
    _resizePreview = clampToBand(resized,
        _document.template.bands[loc.bandIndex], _document.template.page);
    _frameSerial++;
    notifyListeners();
  }

  /// Commits the in-progress resize as one history entry, or clears state.
  void commitResize() {
    final String? id = _resizeId;
    final JetRect? preview = _resizePreview;
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    _resizePreview = null;
    _guides = const <SnapGuide>[];
    _activeBand = null;
    _frameSerial++;
    bool committed = false;
    if (id != null && preview != null) {
      final ({int bandIndex, ReportElement element})? loc = _locate(id);
      if (loc != null && preview != loc.element.bounds) {
        committed = _commit(ResizeCommand(id: id, bounds: preview));
      }
    }
    // Repaint to drop the resize preview + guides even when the resize committed
    // nothing (a clamped no-op), so no guide stays frozen on the canvas.
    if (!committed) notifyListeners();
  }

  /// Discards an in-progress resize.
  void cancelResize() {
    if (_resizeId == null) return;
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    _resizePreview = null;
    _guides = const <SnapGuide>[];
    _activeBand = null;
    _frameSerial++;
    notifyListeners();
  }

  /// Resizes [id] to [bounds] (clamped to its band) as one undoable step — the
  /// committed form used by numeric Properties editing and tests.
  void resizeTo(String id, JetRect bounds) {
    final ({int bandIndex, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    final JetRect clamped = clampToBand(bounds,
        _document.template.bands[loc.bandIndex], _document.template.page);
    if (clamped == loc.element.bounds) return;
    _commit(ResizeCommand(id: id, bounds: clamped));
  }

  // --- Band resize (vertical only) -------------------------------------------
  // A band only has a height; resizing it changes that height. The live
  // interaction previews a height without committing (so the cached frame isn't
  // rebuilt mid-drag), mirroring the element resize lifecycle. The drag's
  // direction-to-height mapping is the caller's concern (a footer grows from its
  // top edge), so [updateBandResize] takes a signed *height* delta.

  int? _bandResizeIndex;
  double? _bandResizeStartHeight;
  double? _bandResizePreviewHeight;

  /// The previewed height of the band at [index] during a live band resize, or
  /// null. The overlay draws the band at this height while dragging the divider.
  double? bandResizePreviewHeight(int index) =>
      _bandResizeIndex == index ? _bandResizePreviewHeight : null;

  /// Begins resizing the band at [index] (no history yet). Out-of-range ignored.
  void beginBandResize(int index) {
    if (index < 0 || index >= _document.template.bands.length) return;
    _bandResizeIndex = index;
    _bandResizeStartHeight = _document.template.bands[index].height;
    _bandResizePreviewHeight = _bandResizeStartHeight;
  }

  /// Updates the in-progress band resize to a cumulative [heightDelta] (points,
  /// positive grows the band), applying the [kMinBandHeight] floor; publishes the
  /// preview.
  void updateBandResize(double heightDelta) {
    final double? start = _bandResizeStartHeight;
    if (start == null) return;
    final double next = start + heightDelta;
    _bandResizePreviewHeight = next < kMinBandHeight ? kMinBandHeight : next;
    _frameSerial++;
    notifyListeners();
  }

  /// Commits the in-progress band resize as one history entry, or clears the
  /// transient state when nothing changed.
  void commitBandResize() {
    final int? index = _bandResizeIndex;
    final double? preview = _bandResizePreviewHeight;
    _bandResizeIndex = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++; // the preview frame is gone; re-record the committed one
    bool committed = false;
    if (index != null && preview != null) {
      committed = _applyBandHeight(index, preview);
    }
    // Repaint to drop the preview even when the resize committed nothing.
    if (!committed) notifyListeners();
  }

  /// Discards an in-progress band resize.
  void cancelBandResize() {
    if (_bandResizeIndex == null) return;
    _bandResizeIndex = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++;
    notifyListeners();
  }

  /// Sets the band at [index]'s height to [height] (floor-clamped) as one
  /// undoable step — the committed form used by numeric editing and tests.
  void setBandHeight(int index, double height) {
    if (index < 0 || index >= _document.template.bands.length) return;
    _applyBandHeight(index, height);
  }

  bool _applyBandHeight(int index, double height) {
    final double clamped = height < kMinBandHeight ? kMinBandHeight : height;
    if (clamped == _document.template.bands[index].height) return false;
    return _commit(SetBandHeightCommand(bandIndex: index, height: clamped));
  }

  /// Sets the report's page [format] — size and/or margins — as one undoable,
  /// notifying step (018 / FR-006/FR-007).
  ///
  /// The Properties panel composes the next [PageFormat] from the live one
  /// (apply a paper preset, swap width/height for orientation, set one margin
  /// side via `copyWith`) and hands the whole value over; this method
  /// [clampPageFormat]s it first so every produced page keeps a positive content
  /// area (FR-009), then commits it. Routed through `_commit`, so a page equal
  /// to the current one records no history and notifies no listener (FR-007),
  /// undo restores the exact prior page, and elements are never repositioned
  /// (FR-013). Canvas, preview, and export all read `template.page`, so the one
  /// notification propagates the change everywhere (WYSIWYG).
  void setPageFormat(PageFormat format) {
    _commit(SetPageFormatCommand(clampPageFormat(format)));
  }

  // --- Numeric geometry + text (Properties / inline) -------------------------

  /// Sets any of [id]'s band-relative x/y/width/height numerically (Properties
  /// panel), clamped to its band, as one undoable step (FR-019).
  void setGeometry(String id,
      {double? x, double? y, double? width, double? height}) {
    final ({int bandIndex, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    final JetRect b = loc.element.bounds;
    final JetRect next = JetRect(
      x: x ?? b.x,
      y: y ?? b.y,
      width: width ?? b.width,
      height: height ?? b.height,
    );
    final JetRect clamped = clampToBand(
        next, _document.template.bands[loc.bandIndex], _document.template.page);
    if (clamped == b) return;
    _commit(ResizeCommand(id: id, bounds: clamped));
  }

  /// Sets the text of the [TextElement] [id] (inline or Properties), one
  /// undoable step (FR-019). No-op for a non-text or absent id.
  void setText(String id, String text) {
    _commit(SetTextCommand(id: id, text: text));
  }

  /// Renames the report to [name] as a single undoable step (017 / FR-008).
  ///
  /// The name is stored verbatim: an empty or whitespace-only name is kept as
  /// `''`, and the UI shows the localized placeholder for an empty name
  /// (FR-010). Renaming to the current name is a no-op — it records no history
  /// entry and notifies no listeners. The new name appears on [template], which
  /// is the value a host persists on save.
  void rename(String name) => _commit(SetTemplateNameCommand(name));

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

  /// Sets the [TextElement] [id] from the unified value field's [raw] text (013).
  ///
  /// Parses the three forms — a `[field]` simple binding, a `{ … }` template, or
  /// literal text (with `\` escapes) — and applies the result as a single
  /// undoable edit (FR-001/002/003/005). No-op for a non-text or absent id.
  void setValue(String id, String raw) {
    final ({int bandIndex, ReportElement element})? loc = _locate(id);
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
  ///
  /// Picking the already-active form is a no-op: it records no history entry and
  /// notifies no listener (FR-005). Switching off a [ShapeKind.line] resets the
  /// line-only diagonal flip, and any deliberate pick clears a preserved
  /// unrecognized form name (FR-009). No-op for a non-shape or absent id.
  void setShapeKind(String id, ShapeKind kind) =>
      _commit(SetShapeKindCommand(id: id, kind: kind));

  /// Replaces the [TextElement] [id]'s whole style with [style] as one
  /// undoable step (021 / FR-001…FR-005), preserving its text, bounds,
  /// binding, and format. Editors build [style] from the current one via
  /// [JetTextStyle.copyWith], so each committed editor change is exactly one
  /// history entry (FR-013).
  ///
  /// Committing an equal style is a no-op: it records no history entry and
  /// notifies no listener. No-op for a non-text or absent id.
  void setTextStyle(String id, JetTextStyle style) =>
      _commit(SetTextStyleCommand(id: id, style: style));

  /// Binds the [ImageElement] [id] to read its picture from the data [field]
  /// (US2 / FR-013). No-op for a non-image or absent id, or when already bound
  /// to the same field.
  void setImageField(String id, String field) {
    _commit(SetImageBindingCommand(id: id, field: field));
  }

  /// Designates the band addressed by [path] (child indices from the top-level
  /// band list; a top-level band is `[index]`) as iterating the nested
  /// [collectionField] for master/detail, or clears it when [collectionField]
  /// is null (US3 / FR-015, FR-015a). One undoable step; no-op for an
  /// out-of-range path or an unchanged binding.
  void setBandCollection(List<int> path, String? collectionField) {
    _commit(SetBandCollectionCommand(
      path: path,
      collectionField: collectionField,
    ));
  }

  List<JetRect> _siblingBounds(int bandIndex, String excludeId) => <JetRect>[
        for (final ReportElement e
            in _document.template.bands[bandIndex].elements)
          if (e.id != excludeId) e.bounds,
      ];

  JetRect _bandBox(int bandIndex) {
    final ReportBand band = _document.template.bands[bandIndex];
    return JetRect(
        x: 0,
        y: 0,
        width: bandContentWidth(_document.template.page),
        height: band.height);
  }

  Map<String, JetRect> _clampedMoveTargets(JetOffset delta) {
    final ReportTemplate t = _document.template;
    final Map<String, JetRect> targets = <String, JetRect>{};
    for (final String id in _document.selection.ids) {
      final ({int bandIndex, ReportElement element})? located = _locate(id);
      if (located == null) continue;
      final JetRect b = located.element.bounds;
      targets[id] = clampToBand(
        JetRect(
          x: b.x + delta.dx,
          y: b.y + delta.dy,
          width: b.width,
          height: b.height,
        ),
        t.bands[located.bandIndex],
        t.page,
      );
    }
    return targets;
  }

  /// Finds the band index and element for [id], or null if not present.
  ({int bandIndex, ReportElement element})? _locate(String id) {
    final bands = _document.template.bands;
    for (int i = 0; i < bands.length; i++) {
      for (final ReportElement element in bands[i].elements) {
        if (element.id == id) return (bandIndex: i, element: element);
      }
    }
    return null;
  }

  // --- Multi-selection -------------------------------------------------------

  /// Selects every element in the template.
  void selectAll() => _setSelection(Selection.of(<String>[
        for (final band in _document.template.bands)
          for (final ReportElement e in band.elements) e.id,
      ]));

  /// Replaces the selection with exactly [ids] (used by marquee select).
  void selectElements(Iterable<String> ids) => _setSelection(Selection.of(ids));

  /// Adds [id] to the selection (shift-click extend).
  void addToSelection(String id) =>
      _setSelection(_document.selection.including(id));

  /// Toggles [id] in/out of the selection (shift-click).
  void toggleSelection(String id) =>
      _setSelection(_document.selection.toggled(id));

  // --- Bulk operations -------------------------------------------------------

  final Clipboard _clipboard = Clipboard();

  /// Deletes the selected elements as one undoable step (FR-014). No-op when the
  /// selection holds no elements (e.g. a band or the report is selected).
  void delete() {
    if (_document.selection.ids.isEmpty) return;
    _commit(DeleteCommand(_document.selection.ids.toSet()));
  }

  /// Moves the selection by a precise nudge (no snapping), one undoable step
  /// (FR-016). Arrow keys pass ±1 pt; Shift+arrow ±10 pt.
  void nudge(double dx, double dy) => moveBy(JetOffset(dx, dy));

  /// Brings the selection one step toward the front (FR-013).
  void bringForward() => _reorder(ReorderMode.forward);

  /// Sends the selection one step toward the back.
  void sendBackward() => _reorder(ReorderMode.backward);

  /// Brings the selection to the very front.
  void bringToFront() => _reorder(ReorderMode.toFront);

  /// Sends the selection to the very back.
  void sendToBack() => _reorder(ReorderMode.toBack);

  void _reorder(ReorderMode mode) {
    if (_document.selection.ids.isEmpty) return;
    _commit(ReorderCommand(_document.selection.ids.toSet(), mode));
  }

  /// Copies the selection to the in-memory clipboard (FR-015).
  ///
  /// A Copy changes derived UI-enablement state ([canPaste] flips `false→true`)
  /// but is **not** a history entry (FR-009) — so it [notifyListeners] to rebuild
  /// the clipboard controls (Paste re-enables after a mouse Copy) WITHOUT routing
  /// through [_commit]. This intentional split between "notify the UI" and
  /// "commit to history" is unique to Copy; every other mutating op does both
  /// through `_commit` (016 / research D1). No-op (no notify) when the selection
  /// holds no elements, so an empty Copy never churns listeners.
  void copy() {
    final List<ClipboardEntry> entries = _collectSelected();
    if (entries.isEmpty) return;
    _clipboard.set(entries);
    notifyListeners();
  }

  /// Cuts: copies the selection, then deletes it (one undoable step).
  void cut() {
    copy();
    delete();
  }

  /// Pastes the clipboard's contents as fresh-id, offset copies, selecting them.
  void paste() {
    if (_clipboard.isEmpty) return;
    final List<ClipboardEntry> copies = _buildCopies(_clipboard.entries);
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// Duplicates the current selection in place (fresh ids + offset), selecting
  /// the copies — without touching the clipboard.
  void duplicate() {
    final List<ClipboardEntry> copies = _buildCopies(_collectSelected());
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// Aligns the (multi-)selection per [kind], one undoable step (FR-012).
  void align(AlignKind kind) =>
      _commitBounds(computeAlign(_collectPositioned(), kind));

  /// Distributes the (multi-)selection evenly along [axis] (FR-012).
  void distribute(DistributeAxis axis) =>
      _commitBounds(computeDistribute(_collectPositioned(), axis));

  void _commitBounds(Map<String, JetRect> newBounds) {
    if (newBounds.isEmpty) return;
    final Map<String, JetRect> clamped = <String, JetRect>{};
    newBounds.forEach((String id, JetRect bounds) {
      final ({int bandIndex, ReportElement element})? loc = _locate(id);
      if (loc == null) return;
      clamped[id] = clampToBand(bounds, _document.template.bands[loc.bandIndex],
          _document.template.page);
    });
    if (clamped.isNotEmpty) _commit(MoveCommand(clamped));
  }

  List<ClipboardEntry> _collectSelected() => <ClipboardEntry>[
        for (final String id in _document.selection.ids)
          if (_locate(id) case final ({int bandIndex, ReportElement element}) l)
            (bandIndex: l.bandIndex, element: l.element),
      ];

  List<Positioned> _collectPositioned() => <Positioned>[
        for (final String id in _document.selection.ids)
          if (_locate(id) case final ({int bandIndex, ReportElement element}) l)
            (id: id, bounds: l.element.bounds),
      ];

  List<ClipboardEntry> _buildCopies(List<ClipboardEntry> source) {
    final List<ClipboardEntry> copies = <ClipboardEntry>[];
    for (final ClipboardEntry entry in source) {
      if (entry.bandIndex < 0 ||
          entry.bandIndex >= _document.template.bands.length) {
        continue;
      }
      final String id = _ids.next(entry.element.typeKey);
      final JetRect b = entry.element.bounds;
      final JetRect offset = clampToBand(
        JetRect(
            x: b.x + kPasteOffset.dx,
            y: b.y + kPasteOffset.dy,
            width: b.width,
            height: b.height),
        _document.template.bands[entry.bandIndex],
        _document.template.page,
      );
      copies.add((
        bandIndex: entry.bandIndex,
        element: cloneElement(entry.element, id: id, bounds: offset),
      ));
    }
    return copies;
  }

  // --- View (zoom / pan) -----------------------------------------------------
  // View state is not part of the model or history; the canvas reads it and the
  // top bar drives it (FR-020).

  double _viewScale = 1.0;
  JetOffset _viewPan = const JetOffset(0, 0);
  int _fitRequest = 0;

  /// The current zoom factor (1.0 == 100%), clamped to [kMinZoom]..[kMaxZoom].
  double get viewScale => _viewScale;

  /// The current pan offset, in screen pixels.
  JetOffset get viewPan => _viewPan;

  /// Increments whenever a fit is requested; the canvas recomputes fit-to-width
  /// (it owns the viewport) and calls [setView].
  int get fitRequest => _fitRequest;

  /// Sets the zoom [scale] (clamped) and [pan] together.
  void setView(double scale, JetOffset pan) {
    final double clamped =
        scale < kMinZoom ? kMinZoom : (scale > kMaxZoom ? kMaxZoom : scale);
    if (clamped == _viewScale && pan == _viewPan) return;
    _viewScale = clamped;
    _viewPan = pan;
    notifyListeners();
  }

  /// Sets just the zoom factor (keeping the current pan).
  void setViewScale(double scale) => setView(scale, _viewPan);

  /// Sets just the pan offset (keeping the current zoom).
  void setViewPan(JetOffset pan) => setView(_viewScale, pan);

  /// Zooms in one step (×1.25).
  void zoomIn() => setViewScale(_viewScale * 1.25);

  /// Zooms out one step (÷1.25).
  void zoomOut() => setViewScale(_viewScale / 1.25);

  /// Requests fit-to-width recentering (fulfilled by the canvas).
  void fitToView() {
    _fitRequest++;
    notifyListeners();
  }

  // --- History ---------------------------------------------------------------

  /// Reverts the last edit, restoring model and selection (no-op if [canUndo]
  /// is false).
  void undo() {
    if (!_history.canUndo) return;
    _document = _history.undo(_document);
    notifyListeners();
  }

  /// Re-applies the last undone edit (no-op if [canRedo] is false).
  void redo() {
    if (!_history.canRedo) return;
    _document = _history.redo(_document);
    notifyListeners();
  }

  /// Applies [command], banks the prior document for undo (clearing redo), and
  /// notifies listeners. Every model-mutating edit goes through here, which is
  /// what makes the whole edit set uniformly undoable.
  /// Applies [command], recording one history entry and notifying listeners.
  /// Returns whether anything actually changed: a no-op command (same template
  /// instance + selection — e.g. set-text to the same value, or a move wholly
  /// absorbed by clamping) records nothing and returns `false`, so a caller that
  /// holds its own transient state (a live move/resize) knows it still owes
  /// listeners a repaint to tear that state down.
  bool _commit(EditCommand command) {
    final DesignerDocument before = _document;
    final DesignerDocument after = command.apply(before);
    if (identical(after.template, before.template) &&
        after.selection == before.selection) {
      return false;
    }
    _document = after;
    _history.push(before);
    notifyListeners();
    return true;
  }

  static String _typeKeyFor(DesignerToolType type) {
    switch (type) {
      case DesignerToolType.text:
        return 'text';
      case DesignerToolType.shape:
        return 'shape';
      case DesignerToolType.image:
        return 'image';
      case DesignerToolType.barcode:
        return 'barcode';
    }
  }
}
