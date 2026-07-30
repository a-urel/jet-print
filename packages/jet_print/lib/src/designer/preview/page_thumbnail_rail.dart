/// The report preview's page-thumbnail rail (044): a lazily-painted, scrollable
/// list of page thumbnails that selects the previewed page.
///
/// Constitution IV (NON-NEGOTIABLE): a thumbnail is the *same* picture the main
/// preview would record — recorded through the shared `paintFrame` →
/// `CanvasPainter` pipeline and blitted through `FrameCustomPainter` at a
/// smaller scale, since a `ui.Picture` is a resolution-independent display
/// list. There is no thumbnail-specific element drawing code.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/page_format.dart';
import '../../rendering/engine/rendered_report.dart';
import '../../rendering/frame/page_frame.dart';
import '../../rendering/paint/canvas_painter.dart';
import '../../rendering/paint/report_painter.dart';
import '../canvas/frame_custom_painter.dart';
import '../l10n/jet_print_localizations.dart';
import 'lru_cache.dart';
import 'preview_sheet.dart';

/// The rail's total width, including the sheet, its padding and the scrollbar
/// gutter. The preview reserves exactly this much when the rail is open.
const double kThumbnailRailWidth = 144;

/// The painted width of one thumbnail sheet.
const double _thumbWidth = 112;

/// The fixed height of the page-number caption under each sheet.
const double _captionHeight = 18;

/// Vertical breathing room below each tile, part of its fixed extent.
const double _tileGap = 10;

/// How many recorded pictures the rail keeps alive at once. Each one also
/// pins any images decoded for that page, so the cap stays modest.
const int _cacheCapacity = 24;

/// A scrollable list of page thumbnails for [report], highlighting
/// [currentIndex] and reporting taps through [onSelect].
///
/// Pages are recorded on demand as their tiles scroll into view and held in a
/// bounded LRU cache, so a long report neither builds every frame up front nor
/// grows an unbounded picture budget.
class PageThumbnailRail extends StatefulWidget {
  /// Creates a thumbnail rail over [report].
  const PageThumbnailRail({
    super.key,
    required this.report,
    required this.currentIndex,
    required this.onSelect,
  });

  /// The rendered report whose pages are listed.
  final RenderedReport report;

  /// The zero-based page currently shown in the preview; its tile is
  /// highlighted and scrolled into view.
  final int currentIndex;

  /// Invoked with the zero-based page index of a tapped thumbnail.
  final ValueChanged<int> onSelect;

  @override
  State<PageThumbnailRail> createState() => PageThumbnailRailState();
}

/// The rail's state. Public (unexported) so widget tests can read
/// [debugCachedCount]; it has no public API beyond that.
class PageThumbnailRailState extends State<PageThumbnailRail> {
  late final LruCache<int, ui.Picture> _pictures = LruCache<int, ui.Picture>(
    capacity: _cacheCapacity,
    onEvict: (ui.Picture picture) => picture.dispose(),
  );

  /// Indices whose record is in flight, so a fast scroll cannot request the
  /// same page twice before the first `await` returns.
  final Set<int> _inFlight = <int>{};

  final ScrollController _controller = ScrollController();

  /// The number of live cached pictures (test seam for the cache cap).
  @visibleForTesting
  int get debugCachedCount => _pictures.length;

  /// The number of records currently awaiting completion (test seam: proves a
  /// throwing record clears its flag instead of leaking it forever).
  @visibleForTesting
  int get debugInFlightCount => _inFlight.length;

  /// The fixed per-tile extent, derived from page 0's aspect ratio. A fixed
  /// extent keeps scrolling O(visible) on a many-page report and makes
  /// scroll-to-index pure arithmetic.
  double get _tileExtent {
    final PageFormat page = widget.report.pageAt(0).frame.page;
    return _thumbWidth * page.height / page.width + _captionHeight + _tileGap;
  }

  @override
  void didUpdateWidget(PageThumbnailRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.report, widget.report)) {
      _pictures.clear();
      _inFlight.clear();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Off the build path: scrolling drives layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCurrent();
      });
    }
  }

  /// Scrolls the current page's tile into view — centred — unless it is
  /// already fully visible. The offset of tile *i* is exactly
  /// `i * _tileExtent` because the list carries no padding and a fixed extent.
  void _revealCurrent() {
    if (!_controller.hasClients) return;
    final double extent = _tileExtent;
    final double top = widget.currentIndex * extent;
    final ScrollPosition position = _controller.position;
    final double viewport = position.viewportDimension;
    if (top >= position.pixels && top + extent <= position.pixels + viewport) {
      return;
    }
    final double target = (top - (viewport - extent) / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pictures.clear();
    _controller.dispose();
    super.dispose();
  }

  /// Records page [index] into a picture through the shared paint pipeline,
  /// then caches it. No-ops while an identical request is in flight; drops the
  /// result if the widget unmounted or the report was swapped meanwhile.
  ///
  /// `paintFrame`/`CanvasPainter.prepare` can throw (a bad font, a corrupt
  /// embedded image, any element-painting exception) — nothing upstream
  /// catches those. Caught here and swallowed rather than rethrown: `_record`
  /// runs fire-and-forget from a post-frame callback with nothing awaiting
  /// it, so a rethrow would surface as an unhandled Future error instead of
  /// leaving a graceful blank tile (matching the engine's own fail-safe
  /// philosophy — `ReportDiagnostics` never throws either). The `finally`
  /// below is what actually matters for correctness: it guarantees
  /// `_inFlight` is cleared on every path, success or failure, so a later
  /// rebuild retries the same index instead of leaving it stuck forever.
  Future<void> _record(int index) async {
    if (_inFlight.contains(index) || _pictures.containsKey(index)) return;
    _inFlight.add(index);
    try {
      final RenderedReport report = widget.report;
      final PageFrame frame = report.pageAt(index).frame;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ReportPainter painter =
          CanvasPainter(ui.Canvas(recorder), report.fonts);
      await paintFrame(frame, painter);
      final ui.Picture picture = recorder.endRecording();
      if (!mounted || !identical(report, widget.report)) {
        picture.dispose();
        return;
      }
      setState(() => _pictures[index] = picture);
    } catch (_) {
      // Best-effort: the tile stays blank and retryable (see the `finally`
      // below), rather than crashing the rail or permanently wedging.
    } finally {
      _inFlight.remove(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return SizedBox(
      width: kThumbnailRailWidth,
      child: ColoredBox(
        color: theme.colorScheme.muted,
        child: ListView.builder(
          key: const ValueKey<String>('jet_print.preview.thumbnails.list'),
          controller: _controller,
          // No list padding: the scroll offset of tile i must stay exactly
          // `i * _tileExtent` for the auto-scroll math.
          padding: EdgeInsets.zero,
          itemExtent: _tileExtent,
          itemCount: widget.report.pageCount,
          itemBuilder: (BuildContext context, int index) {
            final ui.Picture? picture = _pictures[index];
            if (picture == null) {
              // Recording is async and calls setState — schedule it off the
              // build path. `_record` de-duplicates repeated requests.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _record(index);
              });
            }
            return _ThumbnailTile(
              index: index,
              pageCount: widget.report.pageCount,
              page: widget.report.pageAt(index).frame.page,
              picture: picture,
              selected: index == widget.currentIndex,
              onTap: () => widget.onSelect(index),
            );
          },
        ),
      ),
    );
  }
}

/// One thumbnail: a paper sheet painted from [picture] (empty while the record
/// is in flight, matching the main preview), with a page-number caption.
class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.index,
    required this.pageCount,
    required this.page,
    required this.picture,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final int pageCount;
  final PageFormat page;
  final ui.Picture? picture;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final double scale = _thumbWidth / page.width;

    return Semantics(
      // A boundary of its own: each tile is a self-contained interactive
      // unit (a button representing one page), not a fragment that should
      // merge into the list's implicit per-item scrolling node.
      container: true,
      button: true,
      selected: selected,
      label: l10n.previewPageIndicator(index + 1, pageCount),
      onTap: onTap,
      child: GestureDetector(
        // The Semantics above already exposes the tap action and full
        // description; without this, GestureDetector's own implicit gesture
        // semantics node would sit closer to the tile's children than ours,
        // shadowing it for ancestor-based semantics lookups.
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              key: ValueKey<String>('jet_print.preview.thumbnail.$index'),
              width: _thumbWidth,
              height: page.height * scale,
              decoration: BoxDecoration(
                color: previewSheetColor(theme.brightness),
                border: Border.all(
                  color: selected ? colors.primary : colors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: FrameCustomPainter(
                  picture: picture,
                  scale: scale,
                  revision: index,
                ),
              ),
            ),
            SizedBox(
              height: _captionHeight,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: selected
                      ? theme.textTheme.small
                      : theme.textTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
