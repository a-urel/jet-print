import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
class DesignerRightPanel extends StatelessWidget {
  /// Creates the right tabbed panel. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerRightPanel({super.key});

  /// Stable tab identifiers (private; never exported per the API contract).
  static const String _dataSource = 'dataSource';
  static const String _outline = 'outline';
  static const String _properties = 'properties';

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return ColoredBox(
      color: theme.colorScheme.card,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ShadTabs<String>(
          value: _dataSource,
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
