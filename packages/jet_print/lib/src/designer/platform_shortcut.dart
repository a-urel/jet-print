/// Platform-aware keyboard-shortcut hints for the clipboard affordances (016).
///
/// The localized action *label* ("Cut") comes from the ARB files; the modifier
/// glyph is a runtime *platform* fact, not a locale fact, so it is composed here
/// rather than duplicated across every locale (research D6). Apple platforms use
/// the `⌘` glyph; everything else uses the `Ctrl+` prefix.
library;

import 'package:flutter/foundation.dart';

/// The platform modifier prefix: `⌘` on Apple platforms (macOS/iOS), `Ctrl+`
/// elsewhere. Keyed off [defaultTargetPlatform] so a test can pin either branch
/// via `debugDefaultTargetPlatformOverride`.
String shortcutModifier() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.iOS:
      return '⌘';
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return 'Ctrl+';
  }
}

/// The shortcut hint for an action whose accelerator is [letter] (e.g. `'X'`),
/// composed with the platform [shortcutModifier] — `⌘X` or `Ctrl+X`. An empty
/// [letter] yields an empty string, for actions (like Delete) with no modifier.
String shortcutHint(String letter) =>
    letter.isEmpty ? '' : '${shortcutModifier()}$letter';

/// A label suffixed with its parenthesised shortcut hint for a tooltip, e.g.
/// `"Cut (⌘X)"` / `"Cut (Ctrl+X)"`. With an empty [letter] the bare [label] is
/// returned (no empty parentheses).
String labelWithShortcut(String label, String letter) =>
    letter.isEmpty ? label : '$label (${shortcutHint(letter)})';
