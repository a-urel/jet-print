import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/band.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/group_level.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_definition.dart';
import '../../../domain/report_element.dart';
import '../../controller/band_walker.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../controller/selection.dart';
import '../../designer_schema_scope.dart';
import '../../designer_scope.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/element_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../../l10n/object_display_label.dart';
import '../region_chrome.dart';
import '../widgets/editable_label.dart';
import 'scope_field_choices.dart';

part 'outline_panel/type_menu.dart';
part 'outline_panel/rows.dart';
part 'outline_panel/add_menus.dart';

/// Subtle accent tint marking the row whose object is currently selected; matches
/// the canvas selection accent at a low alpha so the highlight reads on white.
const Color _selectedRowColor = Color(0x142563EB);

/// Body of the **Outline** tab: the live report as an indented, collapsible tree
/// reflecting the reified structure (spec 024) — a Report root, the record-blind
/// furniture and once-bands, then the master scope with its first-class groups
/// (each owning its header/footer bands) and nested detail scopes, and a leaf per
/// element (FR-007). The tree is driven entirely by the controller's
/// `definition`/`selection`:
///
/// * the row whose object is selected is highlighted (and marked selected for
///   accessibility);
/// * tapping a row selects that object — the report, a band, a **group**, a
///   **scope**, or an element — through the controller, which the canvas and
///   Properties panel observe;
/// * the disclosure chevron collapses/expands a branch (independent of select).
///
/// Expansion is view state held here (not in the model); it resets when the tab
/// is re-opened, with everything expanded.
class OutlinePanel extends StatefulWidget {
  /// Creates the Outline panel body. Private to the library.
  const OutlinePanel({super.key});

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  bool _rootExpanded = true;

  /// Stable ids of branches (bands, groups, scopes) the user has collapsed
  /// (absent ⇒ expanded). Keyed by id so it survives add/remove/reorder.
  final Set<String> _collapsed = <String>{};

  /// The id of the band or element currently being renamed inline; null means
  /// no inline edit is active.
  String? _editingId;

  // ── Manual double-tap tracking ──────────────────────────────────────────
  // Flutter's GestureDetector delays onTap when onDoubleTap is also present
  // (it waits for the double-tap window). To avoid delaying single-tap
  // selection, we track double-taps manually on the outer onTap handler:
  // two taps on the same node within [_doubleTapWindow] → rename start.
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  String? _lastTappedId;
  Timer? _doubleTapTimer;

  /// Called for every single tap on a row identified by [id].  Fires [onSingle]
  /// immediately; also fires [onDouble] when this tap arrives within
  /// [_doubleTapWindow] of a previous tap on the same [id].
  void _handleTap(String id, VoidCallback onSingle, VoidCallback onDouble) {
    onSingle();
    if (_lastTappedId == id) {
      // Second tap on the same node within the window → double-tap.
      _doubleTapTimer?.cancel();
      _lastTappedId = null;
      onDouble();
    } else {
      // First tap: record and arm the expiry timer.
      _doubleTapTimer?.cancel();
      _lastTappedId = id;
      _doubleTapTimer = Timer(_doubleTapWindow, () => _lastTappedId = null);
    }
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
        // Set.add returns false when already collapsed → expand instead.
        if (!_collapsed.add(id)) _collapsed.remove(id);
      });

  /// Proxy for [setState] callable from the outline's `part` extensions: the
  /// analyzer flags `setState` as protected when reached through an extension,
  /// so the row/menu extensions rebuild through this.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ReportDefinition def = controller.definition;
    final Selection selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final JetDataSchema? schema = DesignerSchemaScope.of(context);

    // If the id being renamed is no longer in the definition or not in the
    // current selection, discard the stale inline editor (synchronous build-
    // time correction — same pattern as properties_panel._editingHeader).
    if (_editingId != null) {
      final bool presentInDef = allIds(def).contains(_editingId!);
      final bool inSelection =
          selection.bandId == _editingId || selection.contains(_editingId!);
      if (!presentInDef || !inSelection) {
        _editingId = null;
      }
    }

    final List<Widget> rows = <Widget>[
      _branchRow(
        rowKey: const ValueKey<String>('jet_print.designer.outline.report'),
        toggleKey:
            const ValueKey<String>('jet_print.designer.outline.report.toggle'),
        depth: 0,
        icon: LucideIcons.fileText,
        label: l10n.reportLabel,
        expanded: _rootExpanded,
        selected: selection.isReport,
        onToggle: () => setState(() => _rootExpanded = !_rootExpanded),
        onSelect: controller.selectReport,
        theme: theme,
        actions: <Widget>[
          _reportAddMenu(controller, theme, l10n),
        ],
      ),
    ];

    if (_rootExpanded) {
      // Record-blind chrome + once-bands above the data body, in visual order.
      for (final Band? band in <Band?>[
        def.furniture.pageHeader,
        def.furniture.columnHeader,
        def.body.title,
      ]) {
        if (band != null) {
          _addBandRows(rows, band, 1, controller, selection, theme, l10n);
        }
      }
      // The data body: the master scope and everything it owns.
      _addScopeRows(
          rows, def.body.root, 1, controller, selection, theme, l10n, schema);
      // Below the data body, in visual order.
      for (final Band? band in <Band?>[
        def.body.noData,
        def.body.summary,
        def.furniture.columnFooter,
        def.furniture.pageFooter,
      ]) {
        if (band != null) {
          _addBandRows(rows, band, 1, controller, selection, theme, l10n);
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}
