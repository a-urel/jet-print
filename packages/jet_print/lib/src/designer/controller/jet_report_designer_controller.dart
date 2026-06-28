/// The public edit-state seam for the report designer.
library;

import 'package:flutter/foundation.dart';

import '../../domain/band.dart';
import '../../domain/bool_property.dart';
import '../../domain/column_layout.dart';
import '../../domain/detail_scope.dart';
import '../../domain/diagnostic.dart';
import '../../domain/elements/barcode_element.dart'
    show BarcodeSymbology, QrErrorCorrectionLevel;
import '../../domain/elements/chart_element.dart' show ChartType;
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
import '../../domain/watermark.dart';
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
import 'commands/rename_band_command.dart';
import 'commands/rename_element_command.dart';
import 'commands/reorder_command.dart';
import 'commands/resize_command.dart';
import 'commands/scope_commands.dart';
import 'commands/set_band_height_command.dart';
import 'commands/set_barcode_color_command.dart';
import 'commands/set_barcode_data_command.dart';
import 'commands/set_barcode_options_command.dart';
import 'commands/set_barcode_symbology_command.dart';
import 'commands/set_binding_command.dart';
import 'commands/set_chart_options_command.dart';
import 'commands/set_column_layout_command.dart';
import 'commands/set_definition_name_command.dart';
import 'commands/set_format_command.dart';
import 'commands/set_page_format_command.dart';
import 'commands/set_shape_kind_command.dart';
import 'commands/set_shape_style_command.dart';
import 'commands/set_text_command.dart';
import 'commands/set_text_style_command.dart';
import 'commands/set_value_command.dart';
import 'commands/set_visible_command.dart';
import 'commands/set_watermark_command.dart';
import 'default_definition.dart';
import 'designer_document.dart';
import 'edit_command.dart';
import 'edit_history.dart';
import 'element_bounds.dart';
import 'element_clone.dart';
import 'element_id_factory.dart';
import 'page_format_clamp.dart';
import 'selection.dart';
import 'snapping.dart';
import 'view_fit_mode.dart';

part 'api/statics.dart';
part 'api/selection.dart';
part 'api/element_edit.dart';
part 'api/barcode.dart';
part 'api/move.dart';
part 'api/resize.dart';
part 'api/bands.dart';
part 'api/groups_scopes.dart';
part 'api/report.dart';
part 'api/clipboard.dart';
part 'api/view.dart';
part 'api/history.dart';

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

  /// Whether the measurement rulers are shown along the canvas's top and left
  /// edges (top-bar toggle; default on, FR-017). A per-session view preference —
  /// like [gridEnabled]/[snapEnabled], it is never serialized into the report.
  /// The canvas reads it to inset its viewport and draw the strips; the top bar
  /// reads it for the ruler toggle's active state.
  bool get rulersEnabled => _rulersEnabled;

  String? _bandResizeId;
  double? _bandResizeStartHeight;
  double? _bandResizePreviewHeight;

  bool _applyBandHeight(String bandId, double height) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null) return false;
    final double clamped = height < kMinBandHeight ? kMinBandHeight : height;
    if (clamped == band.height) return false;
    return _commit(SetBandHeightCommand(bandId: bandId, height: clamped));
  }

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

  /// The move targets for the current selection, moved by [delta] but clamped so
  /// the whole selection stays in-band as a RIGID group.
  ///
  /// The requested [delta] is shrunk to the intersection of every selected
  /// element's in-band range — the most-constrained element limits the group —
  /// then the SAME clamped delta is applied to all. This preserves relative
  /// offsets: a multi-selection pushed against a border stops as one unit instead
  /// of each element piling onto the border (which collapsed the layout). For a
  /// single element the intersection is just that element's range, so the result
  /// is identical to a per-element clamp.
  Map<String, JetRect> _clampedMoveTargets(JetOffset delta) {
    final double maxWidth = bandContentWidth(_document.definition.page);
    final List<({String id, JetRect bounds})> items =
        <({String id, JetRect bounds})>[];
    double loX = double.negativeInfinity, hiX = double.infinity;
    double loY = double.negativeInfinity, hiY = double.infinity;
    for (final String id in _document.selection.ids) {
      final ({Band band, ReportElement element})? located = _locate(id);
      if (located == null) continue;
      final JetRect b = located.element.bounds;
      items.add((id: id, bounds: b));
      // dx keeps x in [0, maxWidth - w]  →  dx in [-x, maxWidth - w - x].
      if (-b.x > loX) loX = -b.x;
      if (maxWidth - b.width - b.x < hiX) hiX = maxWidth - b.width - b.x;
      // dy keeps y in [0, band.height - h], using THIS element's band height.
      if (-b.y > loY) loY = -b.y;
      if (located.band.height - b.height - b.y < hiY) {
        hiY = located.band.height - b.height - b.y;
      }
    }
    // Every in-band element's range contains 0, so the intersection is non-empty
    // (lo <= 0 <= hi). Clamp lower then upper to stay safe if a degenerate
    // oversized element ever inverts the range.
    double dx = delta.dx, dy = delta.dy;
    if (dx < loX) dx = loX;
    if (dx > hiX) dx = hiX;
    if (dy < loY) dy = loY;
    if (dy > hiY) dy = hiY;
    final Map<String, JetRect> targets = <String, JetRect>{};
    for (final ({String id, JetRect bounds}) item in items) {
      targets[item.id] = JetRect(
        x: item.bounds.x + dx,
        y: item.bounds.y + dy,
        width: item.bounds.width,
        height: item.bounds.height,
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

  final Clipboard _clipboard = Clipboard();

  void _reorder(ReorderMode mode) {
    if (_document.selection.ids.isEmpty) return;
    _commit(ReorderCommand(_document.selection.ids.toSet(), mode));
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
  /// Proxy for [notifyListeners] callable from the controller's command
  /// extensions: `notifyListeners` is a protected member, flagged when reached
  /// through an extension, so the command parts notify through this.
  void _notify() => notifyListeners();

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

}
