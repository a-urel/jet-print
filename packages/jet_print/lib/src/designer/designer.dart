/// Designer seam — the user-facing UI and designer widgets.
///
/// This is the outermost layer. It hosts the widgets a consumer renders,
/// including the placeholder component for this iteration.
///
/// Dependency rule: the designer seam may depend on the `rendering`
/// and `domain` seams. Nothing depends on it from inside the library; it is the
/// edge that the public API exposes.
library;
