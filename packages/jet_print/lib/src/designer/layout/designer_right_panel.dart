import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';
import 'panels/data_source_panel.dart';
import 'panels/outline_panel.dart';
import 'panels/properties_panel.dart';

/// The right context panel: a [ShadTabs] hosting the three designer context
/// panels — **Data Source**, **Outline**, **Properties** — in that fixed order,
/// with Data Source active by default (FR-004/005/006).
///
/// `ShadTabs` renders exactly one body at a time and highlights the active tab.
/// `maintainState: false` makes the inactive bodies leave the tree entirely
/// (rather than merely being hidden), giving an unambiguous "exactly one panel
/// visible" guarantee. `expandContent: true` lets the active body fill the
/// panel's height so each panel scrolls within its own bounds (FR-010). Captions
/// come from [JetPrintLocalizations].
///
/// The tab selection is owned by a [ShadTabsController] so a pending
/// `requestPropertiesFocus` (a canvas double-tap) can bring the Properties tab
/// forward — both while mounted (listener) and at mount time (the narrow-layout
/// overlay mounts this panel only after the request fired).
class DesignerRightPanel extends StatefulWidget {
  /// Creates the right tabbed panel. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerRightPanel({super.key});

  @override
  State<DesignerRightPanel> createState() => _DesignerRightPanelState();
}

class _DesignerRightPanelState extends State<DesignerRightPanel> {
  /// Stable tab identifiers (private; never exported per the API contract).
  static const String _dataSource = 'dataSource';
  static const String _outline = 'outline';
  static const String _properties = 'properties';

  final ShadTabsController<String> _tabs =
      ShadTabsController<String>(value: _dataSource);

  /// The designer controller we are subscribed to for focus requests.
  JetReportDesignerController? _bound;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final JetReportDesignerController controller =
        DesignerScope.of(context, listen: false);
    if (!identical(controller, _bound)) {
      _bound?.removeListener(_handleControllerChange);
      _bound = controller;
      _bound!.addListener(_handleControllerChange);
      // A request that fired before this panel existed (the narrow-layout
      // overlay opens first, then mounts this panel) is honored at mount.
      if (controller.pendingPropertiesFocus) _tabs.select(_properties);
    }
  }

  /// Peeks (never consumes — the Properties panel does) at a pending focus
  /// request and brings the Properties tab forward.
  void _handleControllerChange() {
    if (_bound?.pendingPropertiesFocus ?? false) _tabs.select(_properties);
  }

  @override
  void dispose() {
    _bound?.removeListener(_handleControllerChange);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return ColoredBox(
      color: theme.colorScheme.card,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ShadTabs<String>(
          controller: _tabs,
          // Natural-width, horizontally scrollable tab bar: equal-thirds tabs
          // would clip captions like "Data Source" (and longer translations such
          // as German "Eigenschaften") in a narrow panel. Scrollable keeps every
          // caption fully legible at any panel width and in any locale.
          scrollable: true,
          tabs: <ShadTab<String>>[
            ShadTab<String>(
              value: _dataSource,
              expandContent: true,
              maintainState: false,
              content: const DataSourcePanel(),
              child: Text(l10n.tabDataSource),
            ),
            ShadTab<String>(
              value: _outline,
              expandContent: true,
              maintainState: false,
              content: const OutlinePanel(),
              child: Text(l10n.tabOutline),
            ),
            ShadTab<String>(
              value: _properties,
              expandContent: true,
              maintainState: false,
              content: const PropertiesPanel(),
              child: Text(l10n.tabProperties),
            ),
          ],
        ),
      ),
    );
  }
}
