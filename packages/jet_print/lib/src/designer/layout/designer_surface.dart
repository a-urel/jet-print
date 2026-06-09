import 'package:flutter/widgets.dart';

import '../canvas/design_canvas.dart';

/// The center design surface: the interactive WYSIWYG [DesignCanvas] where the
/// report is laid out by direct manipulation.
///
/// Since spec 003 this is a live canvas (replacing the static A4 placeholder of
/// 002): it reads the shared [JetReportDesignerController] from the enclosing
/// `DesignerScope` and paints element appearance through the shared render
/// pipeline (Constitution IV). The surrounding chrome (toolbox, panels, top bar)
/// is composed by `JetReportDesigner`.
class DesignerSurface extends StatelessWidget {
  /// Creates the design surface. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerSurface({super.key});

  @override
  Widget build(BuildContext context) => const DesignCanvas();
}
