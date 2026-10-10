/// The one policy for running a host callback the library invokes — the
/// designer's Save/Open/Preview/Select-data-source and the preview's
/// export/print — and routing its failure.
library;

import 'dart:async';

/// Invoked when a host callback throws, synchronously or via a rejected
/// Future: the designer's Save/Open/Preview/SelectDataSchema callbacks and the
/// preview's export/print callbacks. Receives the [error] and its
/// [stackTrace]. The library performs no file I/O itself, so this surfaces
/// failures the host raised inside its own callbacks. Null ⇒ errors propagate
/// as before (never silently swallowed).
typedef ReportErrorCallback = void Function(
    Object error, StackTrace stackTrace);

/// Runs [run], funnelling any failure to [onError].
///
/// A synchronous throw goes to [onError], or is rethrown when it is null. A
/// returned Future's rejection goes to [onError], or to the current zone when
/// it is null, which is where an un-awaited rejected Future would have gone.
///
/// Returns null when [run] completed synchronously, otherwise a Future that
/// completes, never with an error, once [run]'s Future has settled — so a
/// caller can show a busy state for exactly that long.
Future<void>? runHostCallback(
  FutureOr<void> Function() run,
  ReportErrorCallback? onError,
) {
  final FutureOr<void> result;
  try {
    result = run();
  } catch (error, stackTrace) {
    if (onError == null) rethrow;
    onError(error, stackTrace);
    return null;
  }
  if (result is! Future<void>) return null;
  return result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
    if (onError != null) {
      onError(error, stack);
    } else {
      Zone.current.handleUncaughtError(error, stack);
    }
  });
}
