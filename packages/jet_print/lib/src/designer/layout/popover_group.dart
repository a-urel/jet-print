import 'package:shadcn_ui/shadcn_ui.dart';

/// Coordinates a set of [ShadPopoverController]s so at most one is open at a
/// time: opening any member closes every other open member.
///
/// Toolbar popovers (the page-jump dropdown, the zoom dropdown) each own their
/// own controller. Without coordination two can be open at once; sharing one
/// [PopoverGroup] across them gives "open one ⇒ the other closes" with no
/// coupling between the widgets — each only needs the shared group.
class PopoverGroup {
  final List<ShadPopoverController> _members = <ShadPopoverController>[];
  final Map<ShadPopoverController, void Function()> _listeners =
      <ShadPopoverController, void Function()>{};
  bool _evicting = false;

  /// Registers [controller] as a member. Idempotent.
  void add(ShadPopoverController controller) {
    if (_listeners.containsKey(controller)) return;
    void listener() => _onChanged(controller);
    _members.add(controller);
    _listeners[controller] = listener;
    controller.addListener(listener);
  }

  /// Unregisters [controller]; it no longer participates in eviction.
  void remove(ShadPopoverController controller) {
    final void Function()? listener = _listeners.remove(controller);
    if (listener != null) controller.removeListener(listener);
    _members.remove(controller);
  }

  void _onChanged(ShadPopoverController opened) {
    // Only react to a member that just opened, and guard against the re-entrancy
    // of hiding others (each hide() notifies its own listener).
    if (_evicting || !opened.isOpen) return;
    _evicting = true;
    for (final ShadPopoverController other in _members) {
      if (!identical(other, opened) && other.isOpen) other.hide();
    }
    _evicting = false;
  }

  /// Detaches every listener. Does not dispose the controllers themselves.
  void dispose() {
    for (final MapEntry<ShadPopoverController, void Function()> e
        in _listeners.entries) {
      e.key.removeListener(e.value);
    }
    _listeners.clear();
    _members.clear();
  }
}
