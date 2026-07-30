// White-box unit test for the preview's bounded LRU cache (pure Dart, no
// Flutter): eviction order, access promotion, overwrite and clear all hand the
// dropped value to `onEvict` exactly once, which is what makes the thumbnail
// rail's `ui.Picture` disposal correct.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/preview/lru_cache.dart';

void main() {
  late List<String> evicted;
  LruCache<int, String> cacheOf(int capacity) => LruCache<int, String>(
        capacity: capacity,
        onEvict: evicted.add,
      );

  setUp(() => evicted = <String>[]);

  test('evicts the least recently inserted entry past capacity', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[2] = 'b';
    cache[3] = 'c';

    expect(cache.length, 2);
    expect(cache.containsKey(1), isFalse);
    expect(cache[2], 'b');
    expect(cache[3], 'c');
    expect(evicted, <String>['a']);
  });

  test('reading an entry promotes it, so the other one is evicted next', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[2] = 'b';
    expect(cache[1], 'a'); // promotes 1; 2 is now least-recently used
    cache[3] = 'c';

    expect(cache.containsKey(1), isTrue);
    expect(cache.containsKey(2), isFalse);
    expect(evicted, <String>['b']);
  });

  test('overwriting a key evicts the replaced value', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[1] = 'a2';

    expect(cache.length, 1);
    expect(cache[1], 'a2');
    expect(evicted, <String>['a']);
  });

  test('a missing key reads null and evicts nothing', () {
    final LruCache<int, String> cache = cacheOf(2);
    expect(cache[7], isNull);
    expect(evicted, isEmpty);
  });

  test('clear evicts every entry and empties the cache', () {
    final LruCache<int, String> cache = cacheOf(3);
    cache[1] = 'a';
    cache[2] = 'b';
    cache.clear();

    expect(cache.length, 0);
    expect(evicted, <String>['a', 'b']);
  });
}
