// Page / orientation / line-width previews.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

/// The Office-style page sample in the PAGE section (018): a proportional sheet
/// drawn at the live page's aspect ratio, with a guide rectangle marking the
/// content area (the page inset by its margins). Purely schematic inspector
/// chrome — it reads the same [PageFormat] the canvas/preview/export render, so
/// it always agrees with them, but it is **not** itself a report renderer. It
/// rebuilds whenever the page changes (size, orientation, or a margin).
class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.page});

  final PageFormat page;

  // The sheet fill tracks the canvas paper via the shared `paper_palette`
  // (white in light, slate-200 in dark) so the thumbnail reads as the *same*
  // paper as the design canvas in every theme. The border stays a fixed
  // slate-300 so the sheet keeps a visible edge on either inspector surface.
  static const Color _paperBorder = Color(0xFFCBD5E1); // slate-300
  static const Color _guideColor = Color(0xFF64748B); // slate-500

  /// The preview frame (px) the page is drawn within.
  static const double _frame = 150;

  /// Points mapped to [_frame] px — A4's long side, so the default page nearly
  /// fills the frame and other sizes read relative to it.
  static const double _referenceSide = 842;

  @override
  Widget build(BuildContext context) {
    final bool dark = ShadTheme.of(context).brightness == Brightness.dark;
    // Guard against a degenerate page (the controller clamps to a positive
    // page, but a raw model could be malformed) so the sizing stays finite.
    final double pw = page.width <= 0 ? 1.0 : page.width;
    final double ph = page.height <= 0 ? 1.0 : page.height;
    // Scale points→px so the preview's *size* tracks the page — a larger page
    // reads larger, a smaller one smaller — not just its proportions (US3).
    const double scale = _frame / _referenceSide;
    double w = pw * scale;
    double h = ph * scale;
    // Keep the sheet inside the frame: a page past the reference is fitted down
    // with its proportions preserved.
    final double longest = w > h ? w : h;
    if (longest > _frame) {
      w = w * _frame / longest;
      h = h * _frame / longest;
    }
    return SizedBox(
      key: const ValueKey<String>('$_p.pagePreview'),
      height: _frame,
      child: Center(
        child: SizedBox(
          width: w,
          height: h,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double sheetW = constraints.maxWidth;
              final double sheetH = constraints.maxHeight;
              // The margins map to the same fractions of the scaled sheet, so
              // the guide insets track the real content area proportionally.
              final double l = sheetW * page.margins.left / page.width;
              final double t = sheetH * page.margins.top / page.height;
              final double r = sheetW * page.margins.right / page.width;
              final double b = sheetH * page.margins.bottom / page.height;
              return Stack(
                children: <Widget>[
                  // The paper sheet.
                  Positioned.fill(
                    child: Container(
                      key: const ValueKey<String>('$_p.pagePreview.sheet'),
                      decoration: BoxDecoration(
                        color: paperFill(dark: dark),
                        border: Border.all(color: _paperBorder),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The visible margin chrome: faint shading over the margin
                  // band and a dashed frame around the printable content area,
                  // so even small margins read clearly.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PagePreviewPainter(
                        page: page,
                        guideColor: _guideColor,
                      ),
                    ),
                  ),
                  // A transparent box sized to the content area — the stable
                  // test seam for the guide insets (the painter draws the chrome).
                  Positioned(
                    left: l,
                    top: t,
                    right: r,
                    bottom: b,
                    child: const SizedBox.expand(
                      key: ValueKey<String>('$_p.pagePreview.guide'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
/// Paints the page preview's margin chrome over the sheet: a faint wash over the
/// margin band and a dashed frame around the printable content area, both scaled
/// from the live [PageFormat]'s margins. Schematic only — the canvas/preview/
/// export remain the source of truth for the actual render.
class _PagePreviewPainter extends CustomPainter {
  const _PagePreviewPainter({required this.page, required this.guideColor});

  final PageFormat page;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double l = size.width * page.margins.left / page.width;
    final double t = size.height * page.margins.top / page.height;
    final double r = size.width * page.margins.right / page.width;
    final double b = size.height * page.margins.bottom / page.height;
    final Rect content = Rect.fromLTRB(l, t, size.width - r, size.height - b);
    if (content.width <= 0 || content.height <= 0) return;

    // The sheet stays a single clean paper color (matching the canvas); the
    // printable area is shown by the dashed frame alone — no margin-band wash,
    // which read as a gray tint distinct from the white/​slate paper.
    // Dashed frame around the content area — the margin guide.
    final Paint guide = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _dashedRect(canvas, content, guide);
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    _dashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _dashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _dashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _dashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const double dash = 3, gap = 2;
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      final double end = (d + dash) < total ? d + dash : total;
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) =>
      old.page != page || old.guideColor != guideColor;
}
/// The orientation toggle in the PAGE section (018): a two-segment
/// Portrait | Landscape control in the iOS-style tray (mirroring the workspace
/// mode switch). The active segment reads as a raised tile and is inert;
/// selecting the other emits [onChanged] with the requested orientation, which
/// the panel turns into a width/height swap. Orientation is derived from the
/// page (never stored), so the active segment always reflects the live page.
class _OrientationToggle extends StatelessWidget {
  const _OrientationToggle({
    required this.landscape,
    required this.portraitLabel,
    required this.landscapeLabel,
    required this.onChanged,
  });

  final bool landscape;
  final String portraitLabel;
  final String landscapeLabel;

  /// Fires with the requested orientation (`true` = landscape) when the inactive
  /// segment is selected.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('$_p.field.orientation'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          _segment(
            theme: theme,
            segmentKey:
                const ValueKey<String>('$_p.field.orientation.portrait'),
            icon: LucideIcons.rectangleVertical,
            label: portraitLabel,
            active: !landscape,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          _segment(
            theme: theme,
            segmentKey:
                const ValueKey<String>('$_p.field.orientation.landscape'),
            icon: LucideIcons.rectangleHorizontal,
            label: landscapeLabel,
            active: landscape,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required ShadThemeData theme,
    required Key segmentKey,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    final Color fg = active ? colors.foreground : colors.mutedForeground;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? null : onTap, // selecting the active mode is a no-op
          child: Container(
            key: segmentKey,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? colors.background : const Color(0x00000000),
              borderRadius: BorderRadius.circular(6),
              boxShadow: active
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
/// The outline widths (points) the Appearance row's width picker offers, in
/// ascending order. 0 hides the outline (the color stays remembered). A stored
/// width outside this set still displays as the trigger label. All entries sit
/// inside the legacy [0, 20] bounds.
const List<double> _strokeWidthPresets = <double>[
  0,
  0.5,
  1,
  1.5,
  2,
  3,
  4,
  6,
  8,
  12,
  16,
  20,
];
/// A full-width preview of a stroke [width]: a horizontal rule that fills the
/// space it is given, drawn at the width's thickness (capped to the box so
/// heavy widths stay legible — the numeric label carries the exact value). A
/// width of 0 draws nothing, reading as "no outline". Used by the Appearance
/// row's width picker, trailing the number in both the trigger and the options.
class _LineWidthPreview extends StatelessWidget {
  const _LineWidthPreview({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 16,
      child: Center(
        child: Container(
          width: double.infinity,
          height: width.clamp(0, 14).toDouble(),
          decoration: BoxDecoration(
            color: colors.foreground,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
/// Formats a points value: a whole number drops its decimals, otherwise one.
String _format(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
