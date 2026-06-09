/// The in-memory designer clipboard (cut/copy → paste), session-scoped.
library;

import '../../domain/report_element.dart';

/// One clipboard entry: an [element] and the [bandIndex] it came from, so paste
/// re-inserts it into the same band.
typedef ClipboardEntry = ({int bandIndex, ReportElement element});

/// Holds the last cut/copied elements (FR-015). Immutable elements are stored
/// directly; paste produces fresh-id, offset copies (the controller assigns
/// ids). This is **not** the OS clipboard.
class Clipboard {
  List<ClipboardEntry> _entries = const <ClipboardEntry>[];

  /// Whether there is anything to paste.
  bool get isEmpty => _entries.isEmpty;

  /// The stored entries (unmodifiable).
  List<ClipboardEntry> get entries =>
      List<ClipboardEntry>.unmodifiable(_entries);

  /// Replaces the clipboard contents with [entries].
  void set(List<ClipboardEntry> entries) =>
      _entries = List<ClipboardEntry>.of(entries);
}
