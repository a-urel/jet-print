/// The paper-sheet colour shared by the preview's page surface and its page
/// thumbnails, so the two can never drift apart.
library;

import 'dart:ui' show Brightness, Color;

/// The on-screen colour of a paper sheet under [brightness].
///
/// Pure white in light mode; a slight gray (slate-200) in dark mode so the
/// sheet does not glare against the dark surround. The exported/printed
/// artifact is always white — that is the render pipeline, not this view.
Color previewSheetColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFFFFFFFF);
