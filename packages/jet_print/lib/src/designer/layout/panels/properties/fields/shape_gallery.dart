// The shape-kind gallery and thumbnails.
//
// A part of `properties_panel.dart`: these fields stay
// library-private and share the panel's vocabulary (`_p`,
// `_LabeledRow`, `_NumberField`) without exposing anything.
part of '../../properties_panel.dart';

/// The shape form gallery (020 / US1): a wrap of the [_galleryForms] thumbnails,
/// each drawing its form through the **same** `shapePath` geometry the renderer
/// uses, so the picker icon is exactly what the canvas, preview, and export
/// produce. The thumbnail matching the element's current [ShapeElement.kind] is
/// highlighted — unless the shape carries a preserved [ShapeElement.unknownForm]
/// (it renders as a rectangle, but that is a fallback, not a deliberate choice),
/// or the element is a legacy [ShapeKind.line] (outside the roster), in which
/// case nothing is highlighted. Tapping a thumbnail commits `setShapeKind`;
/// re-picking the active form is a no-op the controller absorbs.
class _ShapeGallery extends StatelessWidget {
  const _ShapeGallery({required this.controller, required this.element});

  final JetReportDesignerController controller;
  final ShapeElement element;

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    // A preserved unknown form (or a legacy line) highlights nothing.
    final ShapeKind? active = element.unknownForm == null ? element.kind : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final ShapeKind kind in _galleryForms)
          _ShapeThumbnail(
            kind: kind,
            label: _shapeFormLabel(kind, l10n),
            active: kind == active,
            onPick: () => controller.setShapeKind(element.id, kind),
          ),
      ],
    );
  }
}
/// One gallery thumbnail: a focusable, keyboard-activatable button drawing the
/// [kind]'s geometry. It carries a localized [label] and `selected`/button
/// semantics (FR-012), highlights when [active] or focused, and runs [onPick]
/// on tap or keyboard activate (Enter/Space).
class _ShapeThumbnail extends StatefulWidget {
  const _ShapeThumbnail({
    required this.kind,
    required this.label,
    required this.active,
    required this.onPick,
  });

  final ShapeKind kind;
  final String label;
  final bool active;
  final VoidCallback onPick;

  @override
  State<_ShapeThumbnail> createState() => _ShapeThumbnailState();
}
class _ShapeThumbnailState extends State<_ShapeThumbnail> {
  static const double _size = 44;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final bool highlighted = widget.active || _focused;
    final Color stroke = widget.active ? colors.primary : colors.foreground;

    return FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPick();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (bool value) => setState(() => _focused = value),
      child: Semantics(
        key: ValueKey<String>('$_p.shape.${widget.kind.name}'),
        button: true,
        enabled: true,
        selected: widget.active,
        label: widget.label,
        onTap: widget.onPick,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPick,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: widget.active ? colors.muted : colors.background,
              border: Border.all(
                color: highlighted ? colors.primary : colors.border,
                width: highlighted ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: CustomPaint(
                painter: _ShapeThumbPainter(kind: widget.kind, color: stroke),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
/// Strokes a single shape form into the thumbnail. Line and rectangle draw their
/// dedicated geometry (mirroring the renderer's special cases); every other form
/// is stroked from the shared `shapePath`, so the thumbnail can never diverge
/// from the rendered shape (C7.4).
class _ShapeThumbPainter extends CustomPainter {
  const _ShapeThumbPainter({required this.kind, required this.color});

  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    switch (kind) {
      case ShapeKind.rectangle:
        canvas.drawRect(Offset.zero & size, paint);
      case ShapeKind.line:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      case ShapeKind.ellipse:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.pentagon:
      case ShapeKind.hexagon:
      case ShapeKind.star:
      case ShapeKind.arrowRight:
      case ShapeKind.arrowLeft:
      case ShapeKind.arrowUp:
      case ShapeKind.arrowDown:
      case ShapeKind.arrowDouble:
      case ShapeKind.chevron:
      case ShapeKind.roundRect:
        canvas.drawPath(
          _toUiPath(shapePath(kind,
              JetRect(x: 0, y: 0, width: size.width, height: size.height))),
          paint,
        );
    }
  }

  /// Replays `shapePath` commands into a `dart:ui` [Path] — the same command set
  /// the canvas and PDF painters replay.
  Path _toUiPath(List<PathCommand> commands) {
    final Path path = Path();
    for (final PathCommand c in commands) {
      switch (c) {
        case MoveTo(:final JetOffset to):
          path.moveTo(to.dx, to.dy);
        case LineTo(:final JetOffset to):
          path.lineTo(to.dx, to.dy);
        case ClosePath():
          path.close();
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_ShapeThumbPainter old) =>
      old.kind != kind || old.color != color;
}
/// The localized accessible name for a shape [kind] (020 / FR-012).
String _shapeFormLabel(ShapeKind kind, JetPrintLocalizations l10n) =>
    switch (kind) {
      ShapeKind.line => l10n.shapeFormLine,
      ShapeKind.rectangle => l10n.shapeFormRectangle,
      ShapeKind.ellipse => l10n.shapeFormEllipse,
      ShapeKind.triangle => l10n.shapeFormTriangle,
      ShapeKind.diamond => l10n.shapeFormDiamond,
      ShapeKind.pentagon => l10n.shapeFormPentagon,
      ShapeKind.hexagon => l10n.shapeFormHexagon,
      ShapeKind.star => l10n.shapeFormStar,
      ShapeKind.arrowRight => l10n.shapeFormArrowRight,
      ShapeKind.arrowLeft => l10n.shapeFormArrowLeft,
      ShapeKind.arrowUp => l10n.shapeFormArrowUp,
      ShapeKind.arrowDown => l10n.shapeFormArrowDown,
      ShapeKind.arrowDouble => l10n.shapeFormArrowDouble,
      ShapeKind.chevron => l10n.shapeFormChevron,
      ShapeKind.roundRect => l10n.shapeFormRoundRect,
    };
/// The closed forms the gallery offers, in roster order.
///
/// [ShapeKind.line] is intentionally absent: a corner-to-corner diagonal is not
/// a useful authoring primitive (a report rule is drawn with a thin rectangle).
/// Line stays a valid `ShapeKind` — pre-existing line elements still load and
/// render unchanged — it is simply not offered here.
const List<ShapeKind> _galleryForms = <ShapeKind>[
  ShapeKind.rectangle,
  ShapeKind.ellipse,
  ShapeKind.triangle,
  ShapeKind.diamond,
  ShapeKind.pentagon,
  ShapeKind.hexagon,
  ShapeKind.star,
  ShapeKind.arrowRight,
  ShapeKind.arrowLeft,
  ShapeKind.arrowUp,
  ShapeKind.arrowDown,
  ShapeKind.arrowDouble,
  ShapeKind.chevron,
  ShapeKind.roundRect,
];
