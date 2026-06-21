/// The on-screen report preview (spec 011 — FR-008/FR-009): a read-only,
/// paginated viewer over a `RenderedReport`.
///
/// Constitution IV (NON-NEGOTIABLE): each page is painted by recording its
/// `RenderedPage.frame` through the **shared** `paintFrame` → `CanvasPainter`
/// pipeline — the identical path the designer's `DesignTimeFrameBuilder`
/// uses — and blitting the recorded picture via the designer's
/// `FrameCustomPainter`. There is no preview-specific element drawing code.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/geometry.dart';
import '../../rendering/engine/rendered_report.dart';
import '../../rendering/frame/page_frame.dart';
import '../../rendering/paint/canvas_painter.dart';
import '../../rendering/paint/report_painter.dart';
import '../../rendering/text/font_registry.dart';
import '../canvas/design_tunables.dart';
import '../canvas/frame_custom_painter.dart';
import '../canvas/zoom_math.dart';
import '../controller/view_fit_mode.dart';
import '../l10n/jet_print_localizations.dart';
import '../layout/page_nav_control.dart';
import '../layout/unified_top_bar.dart';
import '../layout/workspace_mode_switch.dart';
import '../layout/zoom_control.dart';

/// A read-only paginated viewer for a [RenderedReport] (FR-008), with a top
/// toolbar styled to match the designer.
///
/// ```dart
/// final RenderedReport report = const JetReportEngine().render(template, source);
/// // Inside an app that wires JetPrintLocalizations.delegate:
/// Widget preview = JetReportPreview(report: report, onBack: () => pop());
/// ```
///
/// * **Toolbar** — the report's name titles the bar; an optional back button
///   ([onBack]) sits on the leading edge, with the zoom and page-navigation
///   groups on the trailing edge. Chrome is localized (en/de/tr with English
///   fallback) and keyboard/accessible-name operable (FR-017/FR-018).
/// * **Export & print** (012) — optional [onExportPdf]/[onPrint] callbacks
///   each add a localized toolbar action; with both null the toolbar is
///   exactly the 011 widget. The library invokes the callback and nothing
///   else — what export/print means belongs to the host (FR-015).
/// * **Navigation** — previous/next buttons and the left/right arrow keys move
///   one page at a time, bounded at the first/last page; a localized
///   "page X of N" indicator sits between them.
/// * **Zoom** — the *same* zoom section as the designer: zoom out/in buttons
///   flank an editable percentage field whose dropdown offers Fit Width, Fit
///   Page and presets (the shared `ZoomControl`). Opens fit-to-width; "100%"
///   is actual size. The page re-fits on viewport resize while a sticky fit
///   mode is active, and scrolls when zoomed past the viewport.
/// * **Lazy** — pages are requested from the [RenderedReport] on demand, so
///   showing the first page never builds the rest (FR-021).
/// * **WYSIWYG** — the current page paints through the same pipeline as the
///   design surface, so what is previewed is what was designed (FR-009).
///
/// The host must wire `JetPrintLocalizations.delegate` (and the library's
/// supported locales), exactly as for `JetReportDesigner`.
class JetReportPreview extends StatefulWidget {
  /// Creates a preview over [report], opening at [initialPage] (clamped to
  /// the report's page range). When [onBack] is given, a back button appears
  /// on the leading edge of the toolbar.
  const JetReportPreview({
    super.key,
    required this.report,
    this.initialPage = 0,
    this.onBack,
    this.onExportPdf,
    this.onPrint,
    this.onRename,
  });

  /// The rendered report to display.
  final RenderedReport report;

  /// The zero-based page to open at; values outside `[0, pageCount)` are
  /// clamped.
  final int initialPage;

  /// Invoked when the user triggers the toolbar's back button (e.g. to return
  /// to the designer). Null ⇒ no back button is shown.
  final VoidCallback? onBack;

  /// Invoked when the user triggers the toolbar's export action (012,
  /// FR-015). Null ⇒ no export action is shown (the 011 toolbar, unchanged).
  ///
  /// The library only invokes the callback — what "export" means (a save
  /// dialog, a share sheet, an upload) and any busy UI are host concerns;
  /// hosts typically call `JetReportExporter.toPdf` with the same [report].
  final VoidCallback? onExportPdf;

  /// Invoked when the user triggers the toolbar's print action (012,
  /// FR-015). Null ⇒ no print action is shown.
  ///
  /// Hosts typically delegate to `JetReportPrinter.printReport` with the
  /// same [report]; the library itself performs no I/O here.
  final VoidCallback? onPrint;

  /// Reserved hook for renaming the report from the preview (017, FR-008). The
  /// preview no longer surfaces an inline-rename affordance in its toolbar — the
  /// host drives renaming from its own UI — but this callback stays available so
  /// a host can wire it to the same `controller.rename` that backs the designer.
  final ValueChanged<String>? onRename;

  @override
  State<JetReportPreview> createState() => _JetReportPreviewState();
}

class _JetReportPreviewState extends State<JetReportPreview> {
  /// Absolute zoom: `1.0` == 100% == actual size, bounded by the shared
  /// [kMinZoom]/[kMaxZoom] so the preview and designer agree. Manual zoom is a
  /// straight multiplier on this; fit modes compute it from the viewport.
  double _viewScale = 1.0;

  /// The active sticky fit mode. Defaults to fit-to-width (matching the designer
  /// and preserving the preview's prior "opens fit-to-width" behaviour). While
  /// [JetViewFitMode.width]/[JetViewFitMode.page] the page re-fits on viewport
  /// resize; any manual zoom clears it to [JetViewFitMode.none].
  JetViewFitMode _fitMode = JetViewFitMode.width;

  /// The manual zoom step (×/÷ per zoom-in/out press), matching the designer.
  static const double _zoomStep = 1.25;

  /// Fit bookkeeping (mirrors the canvas): [_fitRequest] is bumped on every
  /// explicit fit pick so re-picking the active mode still re-fits;
  /// [_appliedFitRequest]/[_lastFitViewport] guard against redundant fits, and
  /// [_viewInitialized] gates the first-load fit.
  int _fitRequest = 0;
  int _appliedFitRequest = -1;
  Size? _lastFitViewport;
  bool _viewInitialized = false;

  /// Fonts shared between frame recording (the painter resolves glyph bytes
  /// here) and the measurement already baked into the frame, so a glyph is
  /// drawn with the same variant it was measured with. Read off the carried
  /// `RenderedReport` (022) — the registry the engine measured with, including
  /// any host fonts — never a freshly default-only build (Principle IV).
  FontRegistry get _fonts => widget.report.fonts;

  late int _index;

  /// The name shown in the toolbar, taken from the immutable
  /// [RenderedReport.title]; re-seeded whenever the host hands in a fresh report
  /// (e.g. after a rename + re-render).
  late String _displayedName;

  /// The current page's recorded picture, or null while recording is
  /// in-flight (the page box keeps its size; content appears when ready).
  ui.Picture? _picture;

  /// Guards against an out-of-order async record overwriting a newer page.
  int _recordSeq = 0;

  int get _pageCount => widget.report.pageCount;

  PageFrame get _frame => widget.report.pageAt(_index).frame;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage.clamp(0, _pageCount - 1);
    _displayedName = widget.report.title;
    _record();
  }

  @override
  void didUpdateWidget(JetReportPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.report, widget.report)) {
      _index = _index.clamp(0, _pageCount - 1);
      // A fresh report (e.g. the host re-rendered after a rename) re-seeds the
      // displayed name from its title.
      _displayedName = widget.report.title;
      _record();
    }
  }

  @override
  void dispose() {
    _picture?.dispose();
    super.dispose();
  }

  /// Records the current page's frame into a blittable picture through the
  /// shared `paintFrame` → [CanvasPainter] path (async: font load / image
  /// decode happen in `prepare`).
  Future<void> _record() async {
    final int seq = ++_recordSeq;
    final PageFrame frame = _frame;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), _fonts);
    await paintFrame(frame, painter);
    final ui.Picture picture = recorder.endRecording();
    if (!mounted || seq != _recordSeq) {
      picture.dispose();
      return;
    }
    setState(() {
      _picture?.dispose();
      _picture = picture;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= _pageCount || index == _index) return;
    setState(() => _index = index);
    _record();
  }

  /// Manual zoom: set the absolute [scale] (clamped) and drop the sticky fit
  /// mode, so the page no longer re-fits on resize. Mirrors the controller's
  /// `_manualZoom`. Zoom only rescales the already-recorded picture
  /// ([FrameCustomPainter] keys its repaint on the scale), so no re-record.
  void _manualZoom(double scale) {
    setState(() {
      _fitMode = JetViewFitMode.none;
      _viewScale = scale.clamp(kMinZoom, kMaxZoom);
    });
  }

  void _zoomIn() => _manualZoom(_viewScale * _zoomStep);

  void _zoomOut() => _manualZoom(_viewScale / _zoomStep);

  /// Sets the zoom to [percent] % (e.g. 130 → 1.30); manual, so the fit clears.
  void _setZoomPercent(double percent) => _manualZoom(percent / 100);

  /// Selects a sticky fit [mode] and requests a re-fit (computed in the
  /// `LayoutBuilder`, which owns the viewport).
  void _setFitMode(JetViewFitMode mode) {
    setState(() {
      _fitMode = mode;
      _fitRequest++;
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The preview's right-slot actions (017 / FR-011): the page-navigation group
  /// first, then export / print (each only when its callback is wired), then the
  /// zoom group. The preview's buttons are already icon-only, so [compact] is unused;
  /// [veryNarrow] hides the editable zoom % field (the +/- buttons stay), to
  /// match the designer on a phone bar.
  List<Widget> _toolbarActions(
      BuildContext context, bool compact, bool veryNarrow) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return <Widget>[
      // Page-navigation group — prev / "page X of N" / next. Placed FIRST in the
      // toolbar so page selection is the leading control on both the wide and the
      // narrow (scrolling) bar.
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.prev'),
        icon: LucideIcons.chevronLeft,
        label: l10n.previewPreviousPage,
        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
      ),
      // The indicator doubles as a dropdown: First / Last page + "Go to page".
      PageNavControl(
        pageIndex: _index,
        pageCount: _pageCount,
        onGoTo: _goTo,
      ),
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.next'),
        icon: LucideIcons.chevronRight,
        label: l10n.previewNextPage,
        onPressed: _index < _pageCount - 1 ? () => _goTo(_index + 1) : null,
      ),
      const _Divider(),
      // Artifact actions — export / print (012, FR-015): each appears only when
      // its callback is wired; with both null the group is absent (011 parity).
      if (widget.onExportPdf != null || widget.onPrint != null) ...<Widget>[
        if (widget.onExportPdf != null)
          _ToolbarButton(
            buttonKey: const ValueKey<String>('jet_print.preview.export'),
            icon: LucideIcons.fileDown,
            label: l10n.previewExport,
            onPressed: widget.onExportPdf,
          ),
        if (widget.onPrint != null)
          _ToolbarButton(
            buttonKey: const ValueKey<String>('jet_print.preview.print'),
            icon: LucideIcons.printer,
            label: l10n.previewPrint,
            onPressed: widget.onPrint,
          ),
        const _Divider(),
      ],
      // Zoom group — the SAME section as the designer: out / editable % field +
      // Fit Width / Fit Page / preset menu / in. The buttons clamp silently
      // (no disable), matching the designer.
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.zoomOut'),
        icon: LucideIcons.zoomOut,
        label: l10n.actionZoomOutTooltip,
        onPressed: _zoomOut,
      ),
      // The editable zoom % field is hidden on a phone / very narrow bar (the
      // +/- buttons remain), matching the designer.
      if (!veryNarrow)
        ZoomControl(
          viewScale: _viewScale,
          fitMode: _fitMode,
          onPercent: _setZoomPercent,
          onFit: _setFitMode,
          keyPrefix: 'jet_print.preview',
        ),
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.zoomIn'),
        icon: LucideIcons.zoomIn,
        label: l10n.actionZoomInTooltip,
        onPressed: _zoomIn,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: ColoredBox(
        color: colors.muted,
        child: Column(
          children: <Widget>[
            // --- Top toolbar (017): the report name (leading) + the
            // Designer|Preview mode switch (center) are the shared shell's own
            // regions, positionally identical to the designer (FR-001). The
            // right slot carries the preview's own export/print, zoom and
            // page-navigation groups (FR-011). The old standalone back button is
            // folded into the switch's Designer segment, which emits the
            // existing onBack switch request. ---
            UnifiedTopBar(
              // The leading glyph names the report document, identical to the
              // designer's leading icon so the shared region matches in both
              // modes (the preview/inspect cue now lives on the mode switch).
              leadingIcon: LucideIcons.fileText,
              name: _displayedName,
              // The preview's actions are already icon-only and the name
              // ellipsizes to fit; below this width the export/print + zoom +
              // page-nav groups plus the labelled mode switch no longer fit in
              // the longest locale (de/tr), so the whole bar scrolls instead of
              // overflowing (the `compact` flag is unused by the preview).
              compactWidth: 880,
              scrollWidth: 880,
              // The preview's mode switch matches the designer: icon-only on a
              // phone / very narrow bar, labelled otherwise.
              centerBuilder: (BuildContext context, bool veryNarrow) =>
                  WorkspaceModeSwitch(
                mode: WorkspaceMode.preview,
                onSwitchRequested: widget.onBack,
                compact: veryNarrow,
              ),
              actions: _toolbarActions,
            ),
            const ShadSeparator.horizontal(margin: EdgeInsets.zero),
            // --- The page, sized fit-to-width times the zoom factor: centered
            // when it fits, scrolling vertically (always when taller) and
            // horizontally (when zoomed past the viewport). ---
            Expanded(
              child: Semantics(
                container: true,
                label: l10n.previewFitToWidth,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const double pad = 16;
                    final PageFrame frame = _frame;
                    final Size viewport =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final JetSize content =
                        JetSize(frame.page.width, frame.page.height);

                    // Re-fit OFF the build path (it mutates state) on first
                    // load, on an explicit fit pick, or when the viewport
                    // changes while a sticky fit mode is active — the designer
                    // canvas's handshake (design_canvas.dart). Manual zoom
                    // clears the mode, so this leaves a user's scale alone.
                    final bool fitActive = _fitMode != JetViewFitMode.none;
                    final bool viewportChanged = _lastFitViewport != viewport;
                    if ((!_viewInitialized && fitActive) ||
                        _fitRequest != _appliedFitRequest ||
                        (fitActive && viewportChanged)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _viewInitialized = true;
                          _appliedFitRequest = _fitRequest;
                          _lastFitViewport = viewport;
                          _viewScale = _fitMode == JetViewFitMode.page
                              ? fitPageScale(content, viewport, pad)
                              : fitWidthScale(content, viewport, pad);
                        });
                      });
                    }

                    final double scale = _viewScale;
                    final double pageWidth = frame.page.width * scale;
                    final double pageHeight = frame.page.height * scale;
                    // The horizontal scroll content is at least as wide as the
                    // viewport, so the page centers when it fits and scrolls
                    // once zoomed past fit.
                    final double contentWidth =
                        math.max(pageWidth + 2 * pad, viewport.width);
                    return SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Padding(
                            padding: const EdgeInsets.all(pad),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                key: const ValueKey<String>(
                                    'jet_print.preview.page'),
                                width: pageWidth,
                                height: pageHeight,
                                decoration: BoxDecoration(
                                  // Pure white in light mode; a slight gray
                                  // (slate-200) in dark mode so the sheet does
                                  // not glare against the dark surround. The
                                  // exported/printed artifact is always white —
                                  // that is the render pipeline, not this view.
                                  color: theme.brightness == Brightness.dark
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFFFFFFFF),
                                  border: Border.all(color: colors.border),
                                ),
                                child: CustomPaint(
                                  painter: FrameCustomPainter(
                                    picture: _picture,
                                    scale: scale,
                                    revision: _index,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short vertical rule with horizontal breathing room, fencing the toolbar
/// title off from the navigation group (mirrors the designer top bar's
/// `_Divider`).
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 22,
        child: ShadSeparator.vertical(margin: EdgeInsets.zero),
      ),
    );
  }
}

/// A preview toolbar button: tooltip + accessible name over a ghost icon
/// button; renders disabled (null `onPressed`) at its action's bounds (e.g. a
/// nav button at the first/last page, or zoom at its min/max).
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
  });

  final Key? buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ShadTooltip(
      builder: (BuildContext context) => Text(label),
      // The tooltip is hover-only; expose it as the button's accessible name
      // too (the glyph alone is not announced) — FR-018.
      child: MergeSemantics(
        child: Semantics(
          label: label,
          button: true,
          child: ShadIconButton.ghost(
            key: buttonKey,
            icon: Icon(icon, size: 16),
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
