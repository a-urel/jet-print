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

import '../../rendering/engine/rendered_report.dart';
import '../../rendering/frame/page_frame.dart';
import '../../rendering/paint/canvas_painter.dart';
import '../../rendering/paint/report_painter.dart';
import '../../rendering/text/font_registry.dart';
import '../canvas/frame_custom_painter.dart';
import '../l10n/jet_print_localizations.dart';

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
/// * **Navigation** — previous/next buttons and the left/right arrow keys move
///   one page at a time, bounded at the first/last page; a localized
///   "page X of N" indicator sits between them.
/// * **Zoom** — fit-to-width by default (100%); zoom out/in steps the page,
///   tapping the "%" resets to fit, and the page scrolls when zoomed past fit.
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

  @override
  State<JetReportPreview> createState() => _JetReportPreviewState();
}

class _JetReportPreviewState extends State<JetReportPreview> {
  /// The top toolbar's height, matching the designer top bar (`DesignerTopBar`)
  /// so the preview reads as the same workspace.
  static const double _toolbarHeight = 52;

  /// Zoom is a multiplier on the fit-to-width scale: `1.0` fits the page to the
  /// viewport width (the default), values above 1 enlarge it (and the page
  /// scrolls horizontally), values below shrink it. Bounded and stepped like a
  /// document viewer.
  static const double _minZoom = 0.25;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 1.25;

  /// Fonts shared between frame recording (the painter resolves glyph bytes
  /// here) and the measurement already baked into the frame, so a glyph is
  /// drawn with the same variant it was measured with.
  final FontRegistry _fonts = FontRegistry()..registerDefault();

  late int _index;

  /// The fit-to-width zoom multiplier (see [_minZoom]/[_maxZoom]); `1.0` fits.
  double _zoom = 1.0;

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
    _record();
  }

  @override
  void didUpdateWidget(JetReportPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.report, widget.report)) {
      _index = _index.clamp(0, _pageCount - 1);
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

  void _setZoom(double zoom) {
    final double next = zoom.clamp(_minZoom, _maxZoom);
    if (next == _zoom) return;
    // Zoom only rescales the already-recorded picture (FrameCustomPainter keys
    // its repaint on the scale), so no page re-record is needed.
    setState(() => _zoom = next);
  }

  void _zoomIn() => _setZoom(_zoom * _zoomStep);

  void _zoomOut() => _setZoom(_zoom / _zoomStep);

  /// Resets to fit-to-width (100%).
  void _resetZoom() => _setZoom(1.0);

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

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;

    // The report name titles the bar; fall back to the localized "Preview"
    // label when the template is unnamed.
    final String title = widget.report.title.trim().isEmpty
        ? l10n.actionPreview
        : widget.report.title;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: ColoredBox(
        color: colors.muted,
        child: Column(
          children: <Widget>[
            // --- Top toolbar: an optional back button + report name on the
            // leading edge; a zoom group and the page-navigation group on the
            // trailing edge — styled to match the designer's top bar. ---
            ColoredBox(
              color: colors.card,
              child: SizedBox(
                height: _toolbarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 4),
                      if (widget.onBack != null) ...<Widget>[
                        _ToolbarButton(
                          buttonKey:
                              const ValueKey<String>('jet_print.preview.back'),
                          icon: LucideIcons.arrowLeft,
                          label: l10n.previewBack,
                          onPressed: widget.onBack,
                        ),
                        const _Divider(),
                      ],
                      Icon(LucideIcons.eye,
                          size: 18, color: colors.mutedForeground),
                      const SizedBox(width: 10),
                      // The title flexes (ellipsizes first) so the trailing
                      // groups keep their room at narrow widths.
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.large
                              .copyWith(color: colors.foreground),
                        ),
                      ),
                      // Artifact actions group — export / print (012,
                      // FR-015): each appears only when its callback is
                      // wired; with both null the 011 toolbar is unchanged.
                      if (widget.onExportPdf != null ||
                          widget.onPrint != null) ...<Widget>[
                        const _Divider(),
                        if (widget.onExportPdf != null)
                          _ToolbarButton(
                            buttonKey: const ValueKey<String>(
                                'jet_print.preview.export'),
                            icon: LucideIcons.fileDown,
                            label: l10n.previewExport,
                            onPressed: widget.onExportPdf,
                          ),
                        if (widget.onPrint != null)
                          _ToolbarButton(
                            buttonKey: const ValueKey<String>(
                                'jet_print.preview.print'),
                            icon: LucideIcons.printer,
                            label: l10n.previewPrint,
                            onPressed: widget.onPrint,
                          ),
                      ],
                      // Zoom group — out / "%" (tap to fit) / in.
                      const _Divider(),
                      _ToolbarButton(
                        buttonKey:
                            const ValueKey<String>('jet_print.preview.zoomOut'),
                        icon: LucideIcons.zoomOut,
                        label: l10n.actionZoomOutTooltip,
                        onPressed: _zoom > _minZoom ? _zoomOut : null,
                      ),
                      ShadTooltip(
                        builder: (BuildContext context) =>
                            Text(l10n.actionZoomFitTooltip),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _resetZoom,
                          child: SizedBox(
                            width: 46,
                            child: Text(
                              '${(_zoom * 100).round()}%',
                              key: const ValueKey<String>(
                                  'jet_print.preview.zoomLevel'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.small
                                  .copyWith(color: colors.foreground),
                            ),
                          ),
                        ),
                      ),
                      _ToolbarButton(
                        buttonKey:
                            const ValueKey<String>('jet_print.preview.zoomIn'),
                        icon: LucideIcons.zoomIn,
                        label: l10n.actionZoomInTooltip,
                        onPressed: _zoom < _maxZoom ? _zoomIn : null,
                      ),
                      // Page-navigation group — prev / "page X of N" / next.
                      const _Divider(),
                      _ToolbarButton(
                        buttonKey:
                            const ValueKey<String>('jet_print.preview.prev'),
                        icon: LucideIcons.chevronLeft,
                        label: l10n.previewPreviousPage,
                        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          l10n.previewPageIndicator(_index + 1, _pageCount),
                          style: theme.textTheme.small
                              .copyWith(color: colors.foreground),
                        ),
                      ),
                      _ToolbarButton(
                        buttonKey:
                            const ValueKey<String>('jet_print.preview.next'),
                        icon: LucideIcons.chevronRight,
                        label: l10n.previewNextPage,
                        onPressed: _index < _pageCount - 1
                            ? () => _goTo(_index + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
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
                    final double viewportWidth = constraints.maxWidth;
                    final double fitWidth =
                        math.max(0, viewportWidth - 2 * pad);
                    final PageFrame frame = _frame;
                    final double pageWidth = fitWidth * _zoom;
                    final double scale = pageWidth / frame.page.width;
                    final double pageHeight = frame.page.height * scale;
                    // The horizontal scroll content is at least as wide as the
                    // viewport, so the page centers when it fits and scrolls
                    // once zoomed past fit.
                    final double contentWidth =
                        math.max(pageWidth + 2 * pad, viewportWidth);
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
                                  // The paper itself stays white in every app
                                  // theme — the preview shows the printable
                                  // artifact, not a themed widget (WYSIWYG;
                                  // the goldens pin this).
                                  color: const Color(0xFFFFFFFF),
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
