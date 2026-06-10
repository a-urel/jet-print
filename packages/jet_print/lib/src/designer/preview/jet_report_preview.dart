/// The on-screen report preview (spec 011 — FR-008/FR-009): a read-only,
/// paginated viewer over a `RenderedReport`.
///
/// Constitution IV (NON-NEGOTIABLE): each page is painted by recording its
/// `RenderedPage.frame` through the **shared** `paintFrame` → `CanvasPainter`
/// pipeline — the identical path the designer's `DesignTimeFrameBuilder`
/// uses — and blitting the recorded picture via the designer's
/// `FrameCustomPainter`. There is no preview-specific element drawing code.
library;

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

/// A read-only, paginated, fit-to-width viewer for a [RenderedReport]
/// (FR-008; clarification Q3 — no zoom, no editing, no annotation, no print).
///
/// ```dart
/// final RenderedReport report = const JetReportEngine().render(template, source);
/// // Inside an app that wires JetPrintLocalizations.delegate:
/// Widget preview = JetReportPreview(report: report);
/// ```
///
/// * **Navigation** — previous/next buttons and the left/right arrow keys move
///   one page at a time, bounded at the first/last page; a localized
///   "page X of N" indicator sits between them (FR-008/FR-017/FR-018).
/// * **Lazy** — pages are requested from the [RenderedReport] on demand, so
///   showing the first page never builds the rest (FR-021).
/// * **WYSIWYG** — the current page paints through the same pipeline as the
///   design surface, so what is previewed is what was designed (FR-009).
///
/// The host must wire `JetPrintLocalizations.delegate` (and the library's
/// supported locales), exactly as for `JetReportDesigner`.
class JetReportPreview extends StatefulWidget {
  /// Creates a preview over [report], opening at [initialPage] (clamped to
  /// the report's page range).
  const JetReportPreview({
    super.key,
    required this.report,
    this.initialPage = 0,
  });

  /// The rendered report to display.
  final RenderedReport report;

  /// The zero-based page to open at; values outside `[0, pageCount)` are
  /// clamped.
  final int initialPage;

  @override
  State<JetReportPreview> createState() => _JetReportPreviewState();
}

class _JetReportPreviewState extends State<JetReportPreview> {
  /// Fonts shared between frame recording (the painter resolves glyph bytes
  /// here) and the measurement already baked into the frame, so a glyph is
  /// drawn with the same variant it was measured with.
  final FontRegistry _fonts = FontRegistry()..registerDefault();

  late int _index;

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
    final PageFrame frame = _frame;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: ColoredBox(
        color: colors.muted,
        child: Column(
          children: <Widget>[
            // --- Navigation bar: prev / "page X of N" / next. ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _NavButton(
                    buttonKey: const ValueKey<String>('jet_print.preview.prev'),
                    icon: LucideIcons.chevronLeft,
                    label: l10n.previewPreviousPage,
                    onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.previewPageIndicator(_index + 1, _pageCount),
                      style: theme.textTheme.small
                          .copyWith(color: colors.foreground),
                    ),
                  ),
                  _NavButton(
                    buttonKey: const ValueKey<String>('jet_print.preview.next'),
                    icon: LucideIcons.chevronRight,
                    label: l10n.previewNextPage,
                    onPressed: _index < _pageCount - 1
                        ? () => _goTo(_index + 1)
                        : null,
                  ),
                ],
              ),
            ),
            // --- The page, sized fit-to-width (clarification Q3), scrolling
            // vertically when taller than the viewport. ---
            Expanded(
              child: Semantics(
                container: true,
                label: l10n.previewFitToWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double width = constraints.maxWidth;
                      final double scale = width / frame.page.width;
                      return Container(
                        key: const ValueKey<String>('jet_print.preview.page'),
                        width: width,
                        height: frame.page.height * scale,
                        decoration: BoxDecoration(
                          // The paper itself stays white in every app theme —
                          // the preview shows the printable artifact, not a
                          // themed widget (WYSIWYG; the goldens pin this).
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
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A preview navigation button: tooltip + accessible name over a ghost icon
/// button; renders disabled (null `onPressed`) at the page-range bounds.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
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
