import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/jet_print_localizations.dart';
import 'region_chrome.dart';

/// The center design surface: a bounded, paper-like report page floating on a
/// distinct canvas background — the focal "what you're designing" area of the
/// shell, mirroring the document surface in DevExpress/Telerik designers.
///
/// Layout-only this iteration: the page is an empty A4-proportioned sheet that
/// always shows a hint, so it never reads as a blank void (FR-003/FR-007 and the
/// empty-surface edge case). The canvas scrolls independently when the page is
/// taller than the viewport (FR-010). Canvas and page colors both come from
/// [ShadTheme] (FR-008/009); the page uses the card surface so it stays visually
/// distinct from the surrounding chrome.
class DesignerSurface extends StatelessWidget {
  /// Creates the design surface. Private to the library; composed by
  /// `JetReportDesigner`.
  const DesignerSurface({super.key});

  /// ISO 216 portrait aspect ratio (height / width) for the mock page.
  static const double _a4Ratio = 1.4142;
  static const double _maxPageWidth = 560;
  static const double _canvasInset = 28;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return ColoredBox(
      color: colors.muted,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double available = constraints.maxWidth - _canvasInset * 2;
          final double pageWidth =
              math.max(220, math.min(_maxPageWidth, available));
          final double pageHeight = pageWidth * _a4Ratio;

          return SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(_canvasInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    math.max(0, constraints.maxHeight - _canvasInset * 2),
              ),
              child: Center(
                child: ShadCard(
                  width: pageWidth,
                  height: pageHeight,
                  backgroundColor: colors.card,
                  padding: EdgeInsets.zero,
                  // The page keeps its fixed A4 aspect, so its content scrolls
                  // (and stays centered when it fits) rather than overflowing
                  // the sheet on a very small window.
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: pageHeight),
                      child: Center(
                        child: RegionEmptyHint(
                          icon: LucideIcons.filePlus,
                          message: l10n.surfaceEmptyHint,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
