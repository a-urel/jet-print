/// Provides the [JetReportDesignerController] to the designer subtree.
library;

import 'package:flutter/widgets.dart';

import 'controller/jet_report_designer_controller.dart';

/// An [InheritedNotifier] that shares one [JetReportDesignerController] across
/// the canvas and the panels, so a selection or model change in any of them
/// rebuilds the others (FR-018, the cross-panel sync seam).
class DesignerScope extends InheritedNotifier<JetReportDesignerController> {
  /// Wraps [child] with access to [controller].
  const DesignerScope({
    required JetReportDesignerController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The nearest controller above [context]. With [listen] true (the default)
  /// the caller rebuilds when the controller notifies; pass false to read it
  /// once without subscribing (e.g. from a button callback). Asserts one is
  /// present (the designer shell always provides it).
  static JetReportDesignerController of(BuildContext context,
      {bool listen = true}) {
    final DesignerScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<DesignerScope>()
        : context.getInheritedWidgetOfExactType<DesignerScope>();
    assert(scope != null, 'No DesignerScope found above this widget.');
    return scope!.notifier!;
  }
}
