/// Props-based value equality, implemented once.
///
/// Hand-rolled `==`/`hashCode` pairs re-list every field per class — and a
/// base-class field must be repeated in every subclass's pair, which is how a
/// new base field (e.g. a primitive's `rotation`) gets silently ignored by
/// equality. Mixing in [ValueEquality] replaces the pair with a single [props]
/// list; a field is in equality if and only if it is in [props].
library;

/// Value `==`/`hashCode` derived from a [props] list.
///
/// Equality requires the exact same [runtimeType] (every consumer is a leaf
/// type). A [List] entry in [props] compares element-wise (and hashes with
/// [Object.hashAll]), so `List`-valued fields — including byte lists — need no
/// bespoke helpers; nested lists recurse.
///
/// **That element-wise walk is O(content), not O(1)** — which is fine for
/// equality and a trap for caching. `==` and [hashCode] on a value holding a
/// `List` prop cost time proportional to everything in it, so a `Map` or `Set`
/// keyed on such a value pays that on *every* probe, not just on a hit.
/// `ImagePrimitive.bytes` and `TextRunPrimitive.lines` are the two that bite.
/// Both painters' decoded-image caches were once keyed on the whole
/// `ImagePrimitive`, which hashed every byte of every image on every lookup —
/// and, because `bounds` and `elementId` are in `props` too, never hit for a
/// repeated image anyway, so one logo down a band decoded once per row. Both
/// key on the byte buffer now; `PdfPainter._embeddedImages` had always done so,
/// which is what made its sibling `_decoded` look wrong.
///
/// No cache is keyed on a primitive today. `TextRunPrimitive.lines` is the
/// remaining shape to be careful with: nothing caches on a text primitive yet,
/// and anything that starts to would pay the same O(content) probe.
///
/// So: mix this in for equality freely; when caching, key on something O(1)
/// (an identity, an id) rather than on the value itself.
mixin ValueEquality {
  /// The fields participating in equality, in a stable order.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueEquality &&
          other.runtimeType == runtimeType &&
          _propsEqual(other.props, props);

  @override
  int get hashCode => Object.hashAll(props.map(_hashToken));
}

bool _propsEqual(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!_entryEqual(a[i], b[i])) return false;
  }
  return true;
}

bool _entryEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_entryEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Object? _hashToken(Object? v) =>
    v is List ? Object.hashAll(v.map(_hashToken)) : v;
