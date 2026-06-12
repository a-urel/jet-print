/// The unified toolbar's center region: a two-segment **Designer | Preview**
/// control that reflects the active workspace mode and emits a host
/// switch-request when the inactive segment is selected (017 / US1).
///
/// Mode ownership stays with the host (the clarification): the switch never
/// performs the swap itself — it is *told* which mode is active and calls back
/// when the user asks to change it. The composing bars bind that callback to the
/// already-public switch events (`onPreviewRequested` from the designer,
/// `onBack` from the preview), so no new mode API is introduced (FR-002–FR-004,
/// research D2).
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/jet_print_localizations.dart';

/// The workspace the unified toolbar is currently hosting. View-only state —
/// never serialized, owned by the host (data-model §3).
enum WorkspaceMode { designer, preview }

/// A two-segment Designer|Preview switch. [mode] is the active segment (rendered
/// filled and non-actuating); the inactive segment is enabled only when
/// [onSwitchRequested] is wired, and selecting it emits that request.
class WorkspaceModeSwitch extends StatelessWidget {
  /// Creates the switch for the given active [mode]. [onSwitchRequested] fires
  /// when the user selects the *inactive* segment; null leaves it disabled
  /// (mirroring how the Preview action disables on a null `onPreviewRequested`).
  const WorkspaceModeSwitch({
    super.key,
    required this.mode,
    required this.onSwitchRequested,
  });

  /// The currently-active workspace mode (the highlighted segment).
  final WorkspaceMode mode;

  /// Invoked when the inactive segment is selected — the host performs the
  /// actual swap. Null ⇒ the inactive segment renders disabled.
  final VoidCallback? onSwitchRequested;

  /// Stable key on the whole control, so region-parity tests can measure it.
  static const Key switchKey = ValueKey<String>('jet_print.toolbar.modeSwitch');
  static const Key _designerKey =
      ValueKey<String>('jet_print.toolbar.mode.designer');
  static const Key _previewKey =
      ValueKey<String>('jet_print.toolbar.mode.preview');

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final bool designerActive = mode == WorkspaceMode.designer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        key: switchKey,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _segment(
              colors: colors,
              segmentKey: _designerKey,
              // A drafting glyph (pencil + ruler) reads as "design/edit".
              icon: LucideIcons.pencilRuler,
              label: l10n.modeDesigner,
              active: designerActive,
            ),
            const SizedBox(width: 2),
            _segment(
              colors: colors,
              segmentKey: _previewKey,
              // A page-under-magnifier glyph reads as "preview/inspect".
              icon: LucideIcons.fileSearch,
              label: l10n.modePreview,
              active: !designerActive,
            ),
          ],
        ),
      ),
    );
  }

  /// One segment. The active segment reads as a **raised tile** — a
  /// background-colored fill with a subtle shadow and foreground text, so the
  /// current mode clearly stands out against the muted tray (iOS-style
  /// segmented control); actuating it is a no-op (C2.5). The inactive segment is
  /// a transparent ghost button wired to [onSwitchRequested] (disabled when that
  /// is null), with muted-foreground text.
  Widget _segment({
    required ShadColorScheme colors,
    required Key segmentKey,
    required IconData icon,
    required String label,
    required bool active,
  }) {
    // A tight padding keeps the two-segment control compact so it leaves the
    // report name and the mode-specific actions their room on the shared bar.
    const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    final Widget glyph = Icon(icon, size: 14);
    final Widget button = active
        ? ShadButton.secondary(
            key: segmentKey,
            size: ShadButtonSize.sm,
            padding: pad,
            leading: glyph,
            // A raised tile in the page color, lifted off the muted tray so the
            // active mode is unmistakably emphasized in either theme.
            backgroundColor: colors.background,
            hoverBackgroundColor: colors.background,
            foregroundColor: colors.foreground,
            shadows: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
            onPressed: () {}, // selecting the active mode does nothing
            child: Text(label),
          )
        : ShadButton.ghost(
            key: segmentKey,
            size: ShadButtonSize.sm,
            padding: pad,
            leading: glyph,
            foregroundColor: colors.mutedForeground,
            onPressed: onSwitchRequested,
            child: Text(label),
          );
    // The text is the accessible name; `selected` announces the active segment.
    return Semantics(selected: active, child: button);
  }
}
