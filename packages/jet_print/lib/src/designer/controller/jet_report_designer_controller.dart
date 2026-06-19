/// The public edit-state seam for the report designer.
library;

import 'package:flutter/foundation.dart';

import '../../domain/band.dart';
import '../../domain/column_layout.dart';
import '../../domain/detail_scope.dart';
import '../../domain/diagnostic.dart';
import '../../domain/elements/barcode_element.dart'
    show BarcodeSymbology, QrErrorCorrectionLevel;
import '../../domain/elements/shape_element.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/group_level.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart' show BandType;
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import '../../domain/report_validation.dart';
import '../../domain/styles/box_style.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../canvas/design_tunables.dart';
import '../canvas/resize_handle.dart';
import '../template/value_template_compiler.dart';
import 'band_walker.dart';
import 'bulk_geometry.dart';
import 'clipboard.dart';
import 'commands/clipboard_command.dart';
import 'commands/create_element_command.dart';
import 'commands/definition_edit_command.dart';
import 'commands/delete_command.dart';
import 'commands/group_commands.dart';
import 'commands/move_command.dart';
import 'commands/remove_column_layout_command.dart';
import 'commands/reorder_command.dart';
import 'commands/resize_command.dart';
import 'commands/scope_commands.dart';
import 'commands/set_band_height_command.dart';
import 'commands/set_barcode_color_command.dart';
import 'commands/set_barcode_data_command.dart';
import 'commands/set_barcode_options_command.dart';
import 'commands/set_barcode_symbology_command.dart';
import 'commands/set_binding_command.dart';
import 'commands/set_column_layout_command.dart';
import 'commands/set_definition_name_command.dart';
import 'commands/set_format_command.dart';
import 'commands/set_page_format_command.dart';
import 'commands/set_shape_kind_command.dart';
import 'commands/set_shape_style_command.dart';
import 'commands/set_text_command.dart';
import 'commands/set_text_style_command.dart';
import 'commands/set_value_command.dart';
import 'default_definition.dart';
import 'designer_document.dart';
import 'edit_command.dart';
import 'edit_history.dart';
import 'element_bounds.dart';
import 'element_clone.dart';
import 'element_id_factory.dart';
import 'page_format_clamp.dart';
import 'selection.dart';
import 'view_fit_mode.dart';
import 'snapping.dart';

/// Owns the editable design and all editing operations for [JetReportDesigner].
///
/// A [ChangeNotifier] holding the current [definition], the [selection], and an
/// unbounded session undo/redo history of immutable `(definition, selection)`
/// snapshots ([DesignerDocument]). Every state-changing edit funnels through a
/// single [EditCommand] commit path, so:
///
/// * undo/redo restore **both** model and selection exactly (FR-017), and
/// * each operation is a pure, independently-testable transform.
///
/// Reification (spec 024): the model is a [ReportDefinition] section tree, and a
/// band, group, or scope is addressed by its **stable id** (not a flat list
/// index), so selection and edits survive add/remove/reorder. The controller is
/// headless — it performs no filesystem or platform I/O; a host drives save/open
/// via `JetReportFormat` and the designer's `onSaveRequested`/`onOpenRequested`
/// hooks (FR-022).
class JetReportDesignerController extends ChangeNotifier {
  /// Creates a controller over [definition], or a blank default design when none
  /// is supplied (so `JetReportDesignerController()` is drop-in).
  JetReportDesignerController({ReportDefinition? definition})
      : _document = DesignerDocument(
          definition: definition ?? defaultBlankDefinition(),
          selection: Selection.empty,
        ) {
    _ids.seedFrom(_document.definition);
  }

  DesignerDocument _document;
  final EditHistory _history = EditHistory();
  final ElementIdFactory _ids = ElementIdFactory();

  /// The current report model — the value a host saves (FR-022).
  ReportDefinition get definition => _document.definition;

  /// The currently-selected element ids / band / group / scope / report.
  Selection get selection => _document.selection;

  /// Author-time semantic diagnostics for the current [definition] (spec 024 /
  /// C12): duplicate ids/names, a `$F{}` field binding on record-blind
  /// furniture, an unparseable group key, and the like. Recomputed on read and
  /// never throws, so the designer can surface problems live while still holding
  /// a transient invalid state (e.g. a half-typed duplicate name).
  List<Diagnostic> get diagnostics => validate(_document.definition);

  /// Whether an [undo] is available (drives top-bar enablement, US3.4).
  bool get canUndo => _history.canUndo;

  /// Whether a [redo] is available (drives top-bar enablement, US3.4).
  bool get canRedo => _history.canRedo;

  /// Whether the current selection can be cut, copied, duplicated or deleted —
  /// true iff one or more elements are selected (a band/group/scope/report
  /// selection holds no element ids). Both clipboard UI surfaces gate
  /// Cut/Copy/Duplicate/Delete on this single predicate so they cannot diverge
  /// (016 / FR-004, FR-005a, FR-012).
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
  /// stays put — the canvas re-records its cached picture from [displayDefinition]
  /// in realtime during a drag, without a single mid-drag history entry.
  int _frameSerial = 0;

  /// The version of the *displayed* frame: it changes on any committed edit (via
  /// [revision]) **and** on any live drag-preview change (via [_frameSerial]), so
  /// the canvas re-records its cached picture whenever what should be on screen
  /// changes — including mid-drag, when [revision] alone would not move.
  int get frameVersion => revision + _frameSerial;

  /// The definition the canvas should paint: the committed [definition], or —
  /// while a move, element-resize, or band-resize drag is in progress — that
  /// definition with the live drag baked in, so the design follows the pointer in
  /// realtime instead of snapping into place on mouse-up. The committed model is
  /// untouched until commit (one undo step per drag); this is a pure, throwaway
  /// projection rebuilt from the same [MoveCommand] / [ResizeCommand] /
  /// [SetBandHeightCommand] that commit uses, so the live frame and the committed
  /// frame are pixel-identical for the same geometry.
  ///
  /// A band resize reflows every band below it, so the canvas must lay out its
  /// chrome (separators, grid, badges) from *this* definition — not the committed
  /// one — to keep the chrome in step with the live picture (see the canvas's
  /// display-vs-committed layout split).
  ReportDefinition get displayDefinition {
    final JetOffset? move = _moveDelta;
    if (move != null && (move.dx != 0 || move.dy != 0)) {
      final Map<String, JetRect> targets = _clampedMoveTargets(move);
      if (targets.isNotEmpty) {
        return MoveCommand(targets).apply(_document).definition;
      }
    }
    final String? rid = _resizeId;
    final JetRect? preview = _resizePreview;
    if (rid != null && preview != null) {
      return ResizeCommand(id: rid, bounds: preview)
          .apply(_document)
          .definition;
    }
    final String? bid = _bandResizeId;
    final double? height = _bandResizePreviewHeight;
    if (bid != null && height != null) {
      return SetBandHeightCommand(bandId: bid, height: height)
          .apply(_document)
          .definition;
    }
    return _document.definition;
  }

  /// Replaces the whole design with [definition], clearing history and re-seeding
  /// id assignment past the largest existing suffix (FR-004).
  void open(ReportDefinition definition) {
    _pendingPropertiesFocus = false; // stale intent from the prior document
    _document =
        DesignerDocument(definition: definition, selection: Selection.empty);
    _history.clear();
    _ids.seedFrom(definition);
    notifyListeners();
  }

  // --- Selection -------------------------------------------------------------
  // Selection changes are not history entries, but because every snapshot
  // includes the selection, undoing a model edit still restores the prior
  // selection (FR-017).

  /// Selects exactly [id] (replacing any prior selection).
  void select(String id) => _setSelection(Selection.of(<String>[id]));

  /// Selects the band with stable id [bandId] (replacing any prior selection).
  /// Exclusive with element/group/scope/report selection. An unknown id is
  /// ignored.
  void selectBand(String bandId) {
    if (findBand(_document.definition, bandId) == null) return;
    _setSelection(Selection.band(bandId));
  }

  /// Selects the group with stable id [groupId]. An unknown id is ignored.
  void selectGroup(String groupId) {
    if (findGroup(_document.definition, groupId) == null) return;
    _setSelection(Selection.group(groupId));
  }

  /// Selects the scope with stable id [scopeId]. An unknown id is ignored.
  void selectScope(String scopeId) {
    if (findScope(_document.definition, scopeId) == null) return;
    _setSelection(Selection.scope(scopeId));
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
  String? _activeBandId;

  /// The live drag delta during a move interaction (points), or null when no
  /// move is in progress. The selection overlay reads this to draw drag ghosts
  /// without touching the committed model (so the cached frame is not rebuilt
  /// mid-drag).
  JetOffset? get moveDelta => _moveDelta;

  /// Guides (band-relative) currently firing during a live move/resize, for the
  /// overlay to draw (FR-023 / SC-004). Empty when no guide is active.
  List<SnapGuide> get activeGuides => _guides;

  /// The stable id of the band whose element is being moved/resized, so the
  /// overlay can map band-relative guide positions to page coordinates. Null
  /// when idle.
  String? get activeBandId => _activeBandId;

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
    _activeBandId = null;
    final String? single = _document.selection.singleOrNull;
    if (single != null && _snapEnabled && !bypassSnap && threshold > 0) {
      final ({Band band, ReportElement element})? loc = _locate(single);
      if (loc != null) {
        final JetRect b = loc.element.bounds;
        final SnapResult result = snapMove(
          JetRect(
              x: b.x + delta.dx,
              y: b.y + delta.dy,
              width: b.width,
              height: b.height),
          siblings: _siblingBounds(loc.band, single),
          bandBox: _bandBox(loc.band),
          // Grid snapping is governed solely by the snap tool now (D3): we are
          // already inside the `_snapEnabled` guard, so feed the grid candidates
          // unconditionally. `_gridEnabled` controls only the grid's VISIBILITY.
          grid: true,
          gridStep: kGridStep,
          threshold: threshold,
        );
        effective = JetOffset(result.rect.x - b.x, result.rect.y - b.y);
        _guides = result.guides;
        _activeBandId = loc.band.id;
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
    _activeBandId = null;
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
    _activeBandId = null;
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
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    _resizeId = id;
    _resizeHandle = handle;
    _resizeStart = loc.element.bounds;
    _resizePreview = loc.element.bounds;
    _activeBandId = loc.band.id;
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
    final ({Band band, ReportElement element})? loc = _locate(id);
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
        siblings: _siblingBounds(loc.band, id),
        bandBox: _bandBox(loc.band),
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
    _resizePreview = clampToBand(resized, loc.band, _document.definition.page);
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
    _activeBandId = null;
    _frameSerial++;
    bool committed = false;
    if (id != null && preview != null) {
      final ({Band band, ReportElement element})? loc = _locate(id);
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
    _activeBandId = null;
    _frameSerial++;
    notifyListeners();
  }

  /// Resizes [id] to [bounds] (clamped to its band) as one undoable step — the
  /// committed form used by numeric Properties editing and tests.
  void resizeTo(String id, JetRect bounds) {
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    final JetRect clamped =
        clampToBand(bounds, loc.band, _document.definition.page);
    if (clamped == loc.element.bounds) return;
    _commit(ResizeCommand(id: id, bounds: clamped));
  }

  // --- Band resize (vertical only) -------------------------------------------
  // A band only has a height; resizing it changes that height. The live
  // interaction previews a height without committing (so the cached frame isn't
  // rebuilt mid-drag), mirroring the element resize lifecycle. The drag's
  // direction-to-height mapping is the caller's concern (a footer grows from its
  // top edge), so [updateBandResize] takes a signed *height* delta.

  String? _bandResizeId;
  double? _bandResizeStartHeight;
  double? _bandResizePreviewHeight;

  /// The previewed height of band [bandId] during a live band resize, or null.
  /// The overlay draws the band at this height while dragging the divider.
  double? bandResizePreviewHeight(String bandId) =>
      _bandResizeId == bandId ? _bandResizePreviewHeight : null;

  /// Begins resizing the band with stable id [bandId] (no history yet). An
  /// unknown id is ignored.
  void beginBandResize(String bandId) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null) return;
    _bandResizeId = bandId;
    _bandResizeStartHeight = band.height;
    _bandResizePreviewHeight = band.height;
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
    final String? bandId = _bandResizeId;
    final double? preview = _bandResizePreviewHeight;
    _bandResizeId = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++; // the preview frame is gone; re-record the committed one
    bool committed = false;
    if (bandId != null && preview != null) {
      committed = _applyBandHeight(bandId, preview);
    }
    // Repaint to drop the preview even when the resize committed nothing.
    if (!committed) notifyListeners();
  }

  /// Discards an in-progress band resize.
  void cancelBandResize() {
    if (_bandResizeId == null) return;
    _bandResizeId = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++;
    notifyListeners();
  }

  /// Sets band [bandId]'s height to [height] (floor-clamped) as one undoable
  /// step — the committed form used by numeric editing and tests. An unknown id
  /// is ignored.
  void setBandHeight(String bandId, double height) {
    if (findBand(_document.definition, bandId) == null) return;
    _applyBandHeight(bandId, height);
  }

  bool _applyBandHeight(String bandId, double height) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null) return false;
    final double clamped = height < kMinBandHeight ? kMinBandHeight : height;
    if (clamped == band.height) return false;
    return _commit(SetBandHeightCommand(bandId: bandId, height: clamped));
  }

  /// Sets band [bandId]'s multi-column label [layout] as one undoable step
  /// (spec 035). An unknown id is ignored; a value-equal layout records no
  /// history (routed through `_commit`).
  void setColumnLayout(String bandId, ColumnLayout layout) {
    if (findBand(_document.definition, bandId) == null) return;
    _commit(SetColumnLayoutCommand(bandId: bandId, layout: layout));
  }

  /// Clears band [bandId]'s column layout as one undoable step (spec 035). An
  /// unknown id — or a band that already has no layout — is ignored.
  void removeColumnLayout(String bandId) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null || band.columnLayout == null) return;
    _commit(RemoveColumnLayoutCommand(bandId: bandId));
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
  /// (FR-013). Canvas, preview, and export all read `definition.page`, so the one
  /// notification propagates the change everywhere (WYSIWYG).
  void setPageFormat(PageFormat format) {
    _commit(SetPageFormatCommand(clampPageFormat(format)));
  }

  // --- Numeric geometry + text (Properties / inline) -------------------------

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

  /// Renames the report to [name] as a single undoable step (017 / FR-008).
  ///
  /// The name is stored verbatim: an empty or whitespace-only name is kept as
  /// `''`, and the UI shows the localized placeholder for an empty name
  /// (FR-010). Renaming to the current name is a no-op — it records no history
  /// entry and notifies no listeners. The new name appears on [definition],
  /// which is the value a host persists on save.
  void rename(String name) => _commit(SetDefinitionNameCommand(name));

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

  /// Replaces the barcode element [id]'s foreground color with [color] as
  /// one undoable step (021 / FR-011), preserving its symbology, data, and
  /// bounds.
  void setBarcodeColor(String id, JetColor color) =>
      _commit(SetBarcodeColorCommand(id: id, color: color));

  /// Changes the barcode [id]'s symbology.
  void setBarcodeSymbology(String id, BarcodeSymbology symbology) =>
      _commit(SetBarcodeSymbologyCommand(id: id, symbology: symbology));

  /// Sets the barcode [id]'s literal data (clears any bound field).
  void setBarcodeData(String id, String data) =>
      _commit(SetBarcodeDataCommand(id: id, data: data));

  /// Binds the barcode [id]'s value to [field] (null clears the binding).
  void setBarcodeDataField(String id, String? field) =>
      _commit(SetBarcodeDataFieldCommand(id: id, field: field));

  /// Sets the barcode [id]'s data from a value-field [raw] string: a bare
  /// `[field]` token binds the value to that field (keeping the prior literal as
  /// a fallback); any other text is a literal (and clears the binding). Mirrors
  /// [setValue]'s single-input UX, but barcode is field-or-literal — no
  /// expressions (spec 036). One undoable step.
  void setBarcodeValue(String id, String raw) {
    final String? field = parseFieldToken(raw);
    if (field != null) {
      _commit(SetBarcodeDataFieldCommand(id: id, field: field));
    } else {
      _commit(SetBarcodeDataCommand(id: id, data: raw));
    }
  }

  /// Toggles HRI text under the barcode [id].
  void setBarcodeShowText(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, showText: value));

  /// Toggles the quiet zone of the barcode [id].
  void setBarcodeQuietZone(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, quietZone: value));

  /// Sets the QR error-correction level of the barcode [id].
  void setBarcodeEccLevel(String id, QrErrorCorrectionLevel level) =>
      _commit(SetBarcodeOptionsCommand(id: id, eccLevel: level));

  /// Binds the [ImageElement] [id] to read its picture from the data [field]
  /// (US2 / FR-013). No-op for a non-image or absent id, or when already bound
  /// to the same field.
  void setImageField(String id, String field) {
    _commit(SetImageBindingCommand(id: id, field: field));
  }

  // --- Groups & scopes (first-class entities, spec 024 / FR-015) -------------

  /// Adds a new group level (named [name], keyed by [key]) to scope [scopeId] and
  /// selects it, as one undoable step. The new group gets a fresh unique id.
  void createGroup(String scopeId,
      {required String name, required String key}) {
    _commit(CreateGroupCommand(
      scopeId: scopeId,
      group: GroupLevel(id: _ids.next('group'), name: name, key: key),
    ));
  }

  /// Creates a group level on scope [scopeId] keyed to scalar field [fieldName]
  /// (`$F{fieldName}`) and named after it, together with its header band, and
  /// selects the header band — as ONE undoable step. The data-bound creation
  /// path: every authored group is born resolvable against the data source
  /// (spec 026), replacing the placeholder-key path. A no-op for an unknown
  /// scope or a blank [fieldName].
  void createGroupBoundToField(String scopeId, String fieldName) {
    if (fieldName.trim().isEmpty) return;
    if (findScope(_document.definition, scopeId) == null) return;
    final String groupId = _ids.next('group');
    final Band header = Band(
        id: _ids.next('band'),
        type: BandType.groupHeader,
        height: _defaultBandHeight(BandType.groupHeader));
    final GroupLevel group = GroupLevel(
      id: groupId,
      name: fieldName,
      key: '\$F{$fieldName}',
      header: header,
    );
    _commit(DefinitionEditCommand(
      label: 'Add group',
      transform: (ReportDefinition d) => addGroup(d, scopeId, group),
      selection: Selection.band(header.id),
    ));
  }

  /// Removes the group [groupId] (and its header/footer bands) as one undoable
  /// step, clearing the selection.
  void deleteGroup(String groupId) => _commit(DeleteGroupCommand(groupId));

  /// Sets group [groupId]'s grouping [key] expression as one undoable step.
  void setGroupKey(String groupId, String key) => _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group key',
        update: (GroupLevel g) => g.copyWith(key: key),
      ));

  /// Renames group [groupId] (a display label only; groups are referenced by
  /// id, not name) as one undoable step. A no-op for an unknown group or an
  /// unchanged name.
  void setGroupName(String groupId, String name) => _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group name',
        update: (GroupLevel g) => g.copyWith(name: name),
      ));

  /// Sets group [groupId]'s `keepTogether` flag as one undoable step.
  void setGroupKeepTogether(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set keep together',
        update: (GroupLevel g) => g.copyWith(keepTogether: value),
      ));

  /// Sets group [groupId]'s `reprintHeaderOnEachPage` flag as one undoable step.
  void setGroupReprintHeader(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set reprint header',
        update: (GroupLevel g) => g.copyWith(reprintHeaderOnEachPage: value),
      ));

  /// Sets group [groupId]'s `startNewPage` flag — start each instance after the
  /// first on a fresh page — as one undoable step (the 023 feature, now owned by
  /// the group). A no-op (no history) for an unknown group or an unchanged value.
  void setGroupStartNewPage(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group page break',
        update: (GroupLevel g) => g.copyWith(startNewPage: value),
      ));

  /// Adds a nested detail scope iterating [collectionField] under parent scope
  /// [parentScopeId] and selects it, as one undoable step. The new scope gets a
  /// fresh unique id.
  void createScope(String parentScopeId, {String? collectionField}) {
    _commit(CreateScopeCommand(
      parentScopeId: parentScopeId,
      scope:
          DetailScope(id: _ids.next('scope'), collectionField: collectionField),
    ));
  }

  /// Creates a nested list (scope) iterating [collectionField] under
  /// [parentScopeId], pre-populated with one empty detail band, and selects that
  /// band — as ONE undoable step. The data-first entry point used by a Data
  /// Source collection drop/＋ and the Outline "Add list" action to build a
  /// master/detail. A no-op for an unknown parent scope.
  void createListWithBand(String parentScopeId, {String? collectionField}) {
    if (findScope(_document.definition, parentScopeId) == null) return;
    final Band band = Band(
        id: _ids.next('band'),
        type: BandType.detail,
        height: _defaultBandHeight(BandType.detail));
    final DetailScope scope = DetailScope(
      id: _ids.next('scope'),
      collectionField: collectionField,
      children: <ScopeNode>[BandNode(band)],
    );
    _commit(DefinitionEditCommand(
      label: 'Add list',
      transform: (ReportDefinition d) =>
          addScopeChild(d, parentScopeId, NestedScope(scope)),
      selection: Selection.band(band.id),
    ));
  }

  /// Removes the nested scope [scopeId] (and everything it contains) as one
  /// undoable step, clearing the selection.
  void deleteScope(String scopeId) => _commit(DeleteScopeCommand(scopeId));

  /// Sets (or clears, when null) the nested [collectionField] scope [scopeId]
  /// iterates, as one undoable step (US3 / FR-015, FR-015a).
  void setScopeCollection(String scopeId, String? collectionField) => _commit(
        SetScopeCollectionCommand(
            scopeId: scopeId, collectionField: collectionField),
      );

  // --- Band lifecycle (add / remove / reorder / retype — spec 024 / US3) ------

  /// Adds a band to the singleton slot for [type] (a furniture slot, or a body
  /// title/summary/no-data band) and selects it, as one undoable step. A no-op
  /// for a non-singleton [type] or an already-occupied slot.
  void addBand(BandType type) {
    if (!isSingletonSlotType(type)) return;
    if (bandInSlot(_document.definition, type) != null) return;
    final Band band = Band(
        id: _ids.next('band'), type: type, height: _defaultBandHeight(type));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) => setSlotBand(d, type, band),
      selection: Selection.band(band.id),
    ));
  }

  /// Appends a per-row detail band to scope [scopeId] and selects it, as one
  /// undoable step. A no-op for an unknown scope.
  void addDetailBand(String scopeId) {
    if (findScope(_document.definition, scopeId) == null) return;
    final Band band = Band(
        id: _ids.next('band'),
        type: BandType.detail,
        height: _defaultBandHeight(BandType.detail));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) =>
          addScopeChild(d, scopeId, BandNode(band)),
      selection: Selection.band(band.id),
    ));
  }

  /// Adds group [groupId]'s [header] (or footer, when false) band and selects
  /// it, as one undoable step. A no-op for an unknown group or an occupied slot.
  void addGroupBand(String groupId, {required bool header}) {
    final GroupLevel? group = findGroup(_document.definition, groupId);
    if (group == null) return;
    if ((header ? group.header : group.footer) != null) return;
    final BandType type = header ? BandType.groupHeader : BandType.groupFooter;
    final Band band = Band(
        id: _ids.next('band'), type: type, height: _defaultBandHeight(type));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) =>
          setGroupBand(d, groupId, header: header, band: band),
      selection: Selection.band(band.id),
    ));
  }

  /// Removes the band [bandId] wherever it lives (a furniture slot, a body
  /// once-band, a group header/footer, or a scope per-row band) as one undoable
  /// step, clearing the selection. A no-op for an unknown id.
  void removeBand(String bandId) {
    if (findBand(_document.definition, bandId) == null) return;
    _commit(DefinitionEditCommand(
      label: 'Remove band',
      transform: (ReportDefinition d) => removeBandFromTree(d, bandId),
      selection: Selection.empty,
    ));
  }

  /// Moves the per-row band [bandId] by [delta] positions within its scope's
  /// ordered children (negative = toward the front), as one undoable step,
  /// keeping it selected. A no-op when the band is not a scope per-row band or
  /// the move clamps to its current position.
  void moveBand(String bandId, int delta) {
    final DetailScope? scope = findScopeOfBand(_document.definition, bandId);
    if (scope == null) return;
    // Selection is preserved (not forced), so a clamped move — which leaves the
    // definition value-equal — records no history.
    _commit(DefinitionEditCommand(
      label: 'Reorder band',
      transform: (ReportDefinition d) =>
          reorderScopeChild(d, scope.id, bandId, delta),
    ));
  }

  /// Retypes band [bandId] to [newType], relocating it to that type's slot and
  /// updating its [Band.type] (FR-012 / FR-001a) — id, height, and elements are
  /// preserved. Supported for the singleton-slot types (furniture + body
  /// once-bands); a no-op for a non-singleton target, an occupied target slot,
  /// an unknown id, or an unchanged type. One undoable step; the band stays
  /// selected.
  void retypeBand(String bandId, BandType newType) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null || band.type == newType) return;
    if (!isSingletonSlotType(newType)) return;
    if (bandInSlot(_document.definition, newType) != null) return;
    final Band relocated = band.copyWith(type: newType);
    _commit(DefinitionEditCommand(
      label: 'Change band type',
      transform: (ReportDefinition d) =>
          setSlotBand(removeBandFromTree(d, bandId), newType, relocated),
      selection: Selection.band(bandId),
    ));
  }

  /// A sensible default height (points) for a freshly-added band of [type].
  static double _defaultBandHeight(BandType type) => switch (type) {
        BandType.title || BandType.summary => 32,
        BandType.noData => 40,
        BandType.detail => 80,
        BandType.background => 200,
        _ => 24,
      };

  List<JetRect> _siblingBounds(Band band, String excludeId) => <JetRect>[
        for (final ReportElement e in band.elements)
          if (e.id != excludeId) e.bounds,
      ];

  JetRect _bandBox(Band band) => JetRect(
        x: 0,
        y: 0,
        width: bandContentWidth(_document.definition.page),
        height: band.height,
      );

  Map<String, JetRect> _clampedMoveTargets(JetOffset delta) {
    final PageFormat page = _document.definition.page;
    final Map<String, JetRect> targets = <String, JetRect>{};
    for (final String id in _document.selection.ids) {
      final ({Band band, ReportElement element})? located = _locate(id);
      if (located == null) continue;
      final JetRect b = located.element.bounds;
      targets[id] = clampToBand(
        JetRect(
          x: b.x + delta.dx,
          y: b.y + delta.dy,
          width: b.width,
          height: b.height,
        ),
        located.band,
        page,
      );
    }
    return targets;
  }

  /// Finds the band and element for [id], or null if not present.
  ({Band band, ReportElement element})? _locate(String id) {
    final Band? band = findBandOfElement(_document.definition, id);
    if (band == null) return null;
    for (final ReportElement element in band.elements) {
      if (element.id == id) return (band: band, element: element);
    }
    return null;
  }

  // --- Multi-selection -------------------------------------------------------

  /// Selects every element in the definition.
  void selectAll() => _setSelection(Selection.of(<String>[
        for (final Band band in allBands(_document.definition))
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
  /// selection holds no elements (e.g. a band/group/scope or the report).
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
  /// the clipboard controls WITHOUT routing through [_commit]. No-op (no notify)
  /// when the selection holds no elements.
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
    final List<ClipboardEntry> copies =
        _buildCopies(_clipboard.entries, targetBandId: _pasteTargetBand());
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// The band to paste into, or `null` to keep per-source-band paste.
  ///
  /// Returns the explicitly selected band's id only when a band is selected,
  /// that band still exists, and every clipboard entry shares one source band.
  String? _pasteTargetBand() {
    final String? selected = _document.selection.bandId;
    if (selected == null) return null;
    if (findBand(_document.definition, selected) == null) return null;
    final Iterable<String> sources =
        _clipboard.entries.map((ClipboardEntry e) => e.bandId);
    final String first = sources.first;
    if (sources.every((String b) => b == first)) return selected;
    return null;
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
    final PageFormat page = _document.definition.page;
    final Map<String, JetRect> clamped = <String, JetRect>{};
    newBounds.forEach((String id, JetRect bounds) {
      final ({Band band, ReportElement element})? loc = _locate(id);
      if (loc == null) return;
      clamped[id] = clampToBand(bounds, loc.band, page);
    });
    if (clamped.isNotEmpty) _commit(MoveCommand(clamped));
  }

  List<ClipboardEntry> _collectSelected() => <ClipboardEntry>[
        for (final String id in _document.selection.ids)
          if (_locate(id) case final ({Band band, ReportElement element}) l)
            (bandId: l.band.id, element: l.element),
      ];

  List<Positioned> _collectPositioned() => <Positioned>[
        for (final String id in _document.selection.ids)
          if (_locate(id) case final ({Band band, ReportElement element}) l)
            (id: id, bounds: l.element.bounds),
      ];

  List<ClipboardEntry> _buildCopies(List<ClipboardEntry> source,
      {String? targetBandId}) {
    final PageFormat page = _document.definition.page;
    final List<ClipboardEntry> copies = <ClipboardEntry>[];
    for (final ClipboardEntry entry in source) {
      final String destBandId = targetBandId ?? entry.bandId;
      final Band? band = findBand(_document.definition, destBandId);
      if (band == null) continue;
      final String id = _ids.next(entry.element.typeKey);
      final JetRect b = entry.element.bounds;
      // Nudge by +8/+8 only when the copy stays in its own band; across bands
      // keep the original X/Y so it lands where the user expects.
      final JetOffset nudge =
          destBandId == entry.bandId ? kPasteOffset : const JetOffset(0, 0);
      final JetRect placed = clampToBand(
        JetRect(
            x: b.x + nudge.dx,
            y: b.y + nudge.dy,
            width: b.width,
            height: b.height),
        band,
        page,
      );
      copies.add((
        bandId: destBandId,
        element: cloneElement(entry.element, id: id, bounds: placed),
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
  JetViewFitMode _viewFitMode = JetViewFitMode.width;

  /// The current zoom factor (1.0 == 100%), clamped to [kMinZoom]..[kMaxZoom].
  double get viewScale => _viewScale;

  /// The current pan offset, in screen pixels.
  JetOffset get viewPan => _viewPan;

  /// Increments whenever a fit is requested; the canvas recomputes the fit (it
  /// owns the viewport) and calls [setViewScale].
  int get fitRequest => _fitRequest;

  /// The active sticky fit mode. While [JetViewFitMode.width]/[JetViewFitMode.page]
  /// the canvas re-fits on viewport resize; manual zoom clears it to
  /// [JetViewFitMode.none].
  JetViewFitMode get viewFitMode => _viewFitMode;

  /// Sets the zoom [scale] (clamped) and [pan] together. Mode-agnostic on
  /// purpose: the canvas applies a computed fit through here without clearing
  /// the active fit mode.
  void setView(double scale, JetOffset pan) {
    final double clamped =
        scale < kMinZoom ? kMinZoom : (scale > kMaxZoom ? kMaxZoom : scale);
    if (clamped == _viewScale && pan == _viewPan) return;
    _viewScale = clamped;
    _viewPan = pan;
    notifyListeners();
  }

  /// Sets just the zoom factor (keeping the current pan). Mode-agnostic.
  void setViewScale(double scale) => setView(scale, _viewPan);

  /// Sets just the pan offset (keeping the current zoom).
  void setViewPan(JetOffset pan) => setView(_viewScale, pan);

  /// Runs a manual-zoom [apply], clearing the fit mode. If [apply] does not
  /// change the scale (e.g. already at the clamp, or the same value re-entered),
  /// still notifies so a cleared fit mode reaches listeners.
  void _manualZoom(void Function() apply) {
    final bool modeChanged = _viewFitMode != JetViewFitMode.none;
    _viewFitMode = JetViewFitMode.none;
    final double before = _viewScale;
    apply();
    if (modeChanged && _viewScale == before) notifyListeners();
  }

  /// Zooms in one step (×1.25); manual zoom, so the fit mode is cleared.
  void zoomIn() => _manualZoom(() => setViewScale(_viewScale * 1.25));

  /// Zooms out one step (÷1.25); manual zoom, so the fit mode is cleared.
  void zoomOut() => _manualZoom(() => setViewScale(_viewScale / 1.25));

  /// Sets the zoom to [percent] % (e.g. 130 → 1.30), clamped; clears the fit
  /// mode. Used by the editable zoom field and the preset menu rows.
  void setZoomPercent(double percent) =>
      _manualZoom(() => setViewScale(percent / 100));

  /// Multiplies the zoom by [factor] (mouse-wheel zoom); clears the fit mode.
  void zoomBy(double factor) =>
      _manualZoom(() => setViewScale(_viewScale * factor));

  /// Selects a sticky fit [mode] and requests a re-fit (fulfilled by the
  /// canvas, which owns the viewport).
  void setViewFitMode(JetViewFitMode mode) {
    _viewFitMode = mode;
    _fitRequest++;
    notifyListeners();
  }

  /// Back-compat alias: fit the page to the viewport width.
  void fitToView() => setViewFitMode(JetViewFitMode.width);

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
  /// notifies listeners. Returns whether anything actually changed: a no-op
  /// command (one that leaves the definition and selection value-equal — e.g.
  /// set-text to the same value, or a move wholly absorbed by clamping) records
  /// nothing and returns `false`, so a caller that holds its own transient state
  /// (a live move/resize) knows it still owes listeners a repaint to tear that
  /// state down.
  ///
  /// No-op detection is by **value** equality (not identity): the reified
  /// tree-transform helpers rebuild structure freely, so `==` — not `identical`
  /// — is what tells a real edit from a no-op.
  bool _commit(EditCommand command) {
    final DesignerDocument before = _document;
    final DesignerDocument after = command.apply(before);
    if (after.definition == before.definition &&
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
