/// The environment passed to an [ElementRenderer]'s measure/emit (spec 007a).
///
/// In 007a it carries only the [TextMeasurer]; a diagnostics sink is added here
/// in 007b without changing renderer signatures. It deliberately exposes neither
/// resolved values (renderers render the element they are handed — the
/// resolved-element seam) nor a separate `FontRegistry` (the measurer is the
/// single font authority via `MeasuredText.fontFamily`).
library;

import '../text/text_measurer.dart';

/// Carries the shared text-measurement environment for a render pass.
class RenderContext {
  /// Creates a context over [measurer].
  const RenderContext({required this.measurer});

  /// Lays out text into lines (and reports the resolved font family).
  final TextMeasurer measurer;
}
