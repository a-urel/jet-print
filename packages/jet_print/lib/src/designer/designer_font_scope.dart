/// Provides the designer's one [FontRegistry] to the designer subtree (021).
library;

import 'package:flutter/widgets.dart';

import '../rendering/text/font_registry.dart';

/// An [InheritedWidget] sharing the designer's single hoisted [FontRegistry]
/// with the canvas frame builder and the Properties panel's family picker, so
/// the family set the picker enumerates is provably the set the canvas
/// measures and paints with (021 / research §1 — WYSIWYG by construction).
///
/// The registry itself stays **internal**: no public host-registration seam
/// opens here, because a designer-only family would silently fall back in
/// preview/export (Constitution IV). When a host-font seam lands as its own
/// feature, this scope is where the designer side picks it up.
class DesignerFontScope extends InheritedWidget {
  /// Shares [fonts] with [child].
  const DesignerFontScope({
    required this.fonts,
    required super.child,
    super.key,
  });

  /// The designer's font registry (default font pre-registered).
  final FontRegistry fonts;

  /// The nearest registry above [context]. Falls back to a fresh default-only
  /// registry when no scope is present (e.g. a panel pumped in isolation) —
  /// the same family set the engine/preview/exporter construct today.
  static FontRegistry of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignerFontScope>()?.fonts ??
      (FontRegistry()..registerDefault());

  @override
  bool updateShouldNotify(DesignerFontScope oldWidget) =>
      !identical(oldWidget.fonts, fonts);
}
