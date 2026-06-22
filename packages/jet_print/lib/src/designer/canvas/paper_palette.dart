/// The on-screen paper fill, shared by the design canvas and the Properties
/// page-orientation thumbnail so the thumbnail always reads as the *same* paper
/// as the canvas (they previously held independent copies and drifted: the
/// thumbnail stayed pure white in dark mode while the canvas paper is slate-200).
///
/// White in light mode; a slight gray (slate-200) in dark mode — light enough to
/// read as paper and to carry dark print content, dim enough not to glare
/// against the dark surround. The actual exported/printed artifact is always
/// white: that is the render pipeline, not this on-screen chrome.
library;

import 'package:flutter/widgets.dart';

/// The paper fill in light mode (pure white).
const Color kPaperColorLight = Color(0xFFFFFFFF);

/// The paper fill in dark mode (slate-200 — a slight gray, not white).
const Color kPaperColorDark = Color(0xFFE2E8F0);

/// Resolves the paper fill for the active theme [dark]ness.
Color paperFill({required bool dark}) =>
    dark ? kPaperColorDark : kPaperColorLight;
