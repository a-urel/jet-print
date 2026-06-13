/// Provides the designer's one [FontRegistry] to the designer subtree (021).
library;

import 'package:flutter/widgets.dart';

import '../rendering/text/font_registry.dart';

/// An [InheritedWidget] sharing the designer's single hoisted [FontRegistry]
/// with the canvas frame builder and the Properties panel's family picker, so
/// the family set the picker enumerates is provably the set the canvas
/// measures and paints with (021 / research §1 — WYSIWYG by construction).
///
/// The registry itself stays **internal**; host fonts reach it via
/// `JetReportDesigner.fonts` (022), which the designer layers on top of the
/// built-in defaults before building this scope.
class DesignerFontScope extends InheritedWidget {
  /// Shares [fonts] with [child].
  const DesignerFontScope({
    required this.fonts,
    required super.child,
    this.showBuiltIns = true,
    super.key,
  });

  /// The designer's font registry (default font pre-registered).
  final FontRegistry fonts;

  /// Whether the bundled built-in families (JetSans/JetSerif/JetMono) are
  /// offered as **selectable options** in the family picker (022). They are
  /// always present in [fonts] — JetSans is the render fallback — so this only
  /// controls picker visibility, never resolvability. Defaults to true
  /// (backward-compatible).
  final bool showBuiltIns;

  /// The nearest registry above [context]. Falls back to a fresh default-only
  /// registry when no scope is present (e.g. a panel pumped in isolation) —
  /// the same family set the engine/preview/exporter construct today.
  static FontRegistry of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignerFontScope>()?.fonts ??
      (FontRegistry()..registerDefault());

  /// Whether the picker should offer the built-in families above [context]
  /// (defaults to true when no scope is present).
  static bool showBuiltInsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DesignerFontScope>()
          ?.showBuiltIns ??
      true;

  @override
  bool updateShouldNotify(DesignerFontScope oldWidget) =>
      !identical(oldWidget.fonts, fonts) ||
      oldWidget.showBuiltIns != showBuiltIns;
}
