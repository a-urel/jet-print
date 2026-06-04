import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A minimal, theme-aware placeholder component for the `jet_print` library.
///
/// This is the one renderable widget the scaffold exposes. Its job is to prove
/// end-to-end consumption: an external consumer can import only
/// `package:jet_print/jet_print.dart`, drop this widget into their tree, and see
/// it pick up the surrounding [shadcn theme](https://pub.dev/packages/shadcn_ui).
///
/// All of its colors and text styles are read from [ShadTheme.of], so switching
/// the active [ShadThemeData] (for example, light ↔ dark) visibly changes its
/// appearance — there are no hardcoded colors (satisfies SC-006).
///
/// It builds without any ancestor beyond a standard `ShadApp` (or other
/// `ShadTheme` provider) shell and requires no host-application state.
///
/// ```dart
/// ShadApp(
///   home: Center(child: JetPrintPlaceholder()),
/// );
/// ```
class JetPrintPlaceholder extends StatelessWidget {
  /// Creates a placeholder component.
  ///
  /// It is `const`-constructible so consumers can use it in `const` widget
  /// trees with zero runtime cost.
  const JetPrintPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: theme.radius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'jet_print',
              style: theme.textTheme.h4.copyWith(color: colors.cardForeground),
            ),
            const SizedBox(height: 8),
            Text(
              'Placeholder component — the report designer goes here.',
              style:
                  theme.textTheme.muted.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
