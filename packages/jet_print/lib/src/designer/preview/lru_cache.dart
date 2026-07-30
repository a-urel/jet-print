/// A bounded least-recently-used map with an eviction hook.
///
/// Kept deliberately Flutter-free (Principle III) so the eviction math is
/// unit-testable in isolation from the widget that owns it. The preview's
/// thumbnail rail uses it to bound how many recorded `ui.Picture`s it holds,
/// disposing whatever falls out.
library;

/// A map of at most [capacity] entries; inserting past that evicts the
/// least-recently-used entry through [onEvict].
///
/// "Used" means read via `[]` or written via `[]=`. [onEvict] is called for a
/// dropped value exactly once: on eviction, on overwrite of an existing key,
/// and for every remaining entry on [clear].
class LruCache<K, V extends Object> {
  /// Creates a cache holding at most [capacity] entries (must be positive),
  /// handing every dropped value to [onEvict].
  LruCache({required this.capacity, required this.onEvict})
      : assert(capacity > 0, 'capacity must be positive');

  /// The maximum number of live entries.
  final int capacity;

  /// Invoked with each value the cache drops, so the owner can release it.
  final void Function(V value) onEvict;

  /// Insertion-ordered: the first key is the least recently used, because both
  /// reads and writes re-insert their entry at the end.
  final Map<K, V> _entries = <K, V>{};

  /// The number of live entries (never above [capacity]).
  int get length => _entries.length;

  /// Whether [key] currently holds a value, without promoting it.
  bool containsKey(K key) => _entries.containsKey(key);

  /// The value for [key], promoting it to most-recently-used; null if absent.
  V? operator [](K key) {
    final V? value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// Stores [value] under [key] as most-recently-used, evicting the replaced
  /// value (if any) and then the least-recently-used entries past [capacity].
  void operator []=(K key, V value) {
    final V? replaced = _entries.remove(key);
    if (replaced != null) onEvict(replaced);
    _entries[key] = value;
    while (_entries.length > capacity) {
      final K oldest = _entries.keys.first;
      onEvict(_entries.remove(oldest)!);
    }
  }

  /// Drops every entry, evicting each one.
  void clear() {
    for (final V value in _entries.values) {
      onEvict(value);
    }
    _entries.clear();
  }
}
