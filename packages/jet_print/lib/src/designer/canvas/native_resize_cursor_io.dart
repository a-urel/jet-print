/// macOS implementation of [setNativeDiagonalResizeCursor] (see the facade in
/// `native_resize_cursor.dart`).
///
/// macOS exposes diagonal resize cursors only as *private* `NSCursor` class
/// methods used for window resizing. We invoke them through the Objective-C
/// runtime via `dart:ffi` — no native plugin code, and the selector is built
/// from a string at runtime (`sel_registerName`) rather than referenced as a
/// link-time symbol. A `respondsToSelector:` guard means that if a future macOS
/// drops the selector we simply return `false` and the caller falls back to a
/// (non-diagonal) system cursor.
library;

import 'dart:ffi';
import 'dart:io' show Platform;

// objc_getClass / sel_registerName take a C string (`const char*`); we model it
// as `Pointer<Uint8>` (same ABI). objc_msgSend is looked up once per call shape
// because the FFI trampoline depends on the return/argument types.
typedef _PtrFromCStrNative = Pointer<Void> Function(Pointer<Uint8>);
typedef _PtrFromCStrDart = Pointer<Void> Function(Pointer<Uint8>);
typedef _MsgSendIdNative = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendIdDart = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendVoidNative = Void Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendVoidDart = void Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendBoolNative = Uint8 Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _MsgSendBoolDart = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _MallocNative = Pointer<Uint8> Function(IntPtr);
typedef _MallocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);

/// See `native_resize_cursor.dart`.
bool setNativeDiagonalResizeCursor({required bool northEastSouthWest}) {
  if (!Platform.isMacOS) return false;
  final _NsCursorBridge? bridge = _NsCursorBridge.instance;
  return bridge != null && bridge.setDiagonal(northEastSouthWest);
}

/// Cached Objective-C runtime handles for setting the diagonal `NSCursor`.
///
/// Resolved once and reused; `null` if the runtime symbols can't be bound (which
/// should never happen on a real macOS host, but keeps us defensive).
class _NsCursorBridge {
  _NsCursorBridge._({
    required _MsgSendIdDart msgSendId,
    required _MsgSendVoidDart msgSendVoid,
    required _MsgSendBoolDart msgSendBool,
    required Pointer<Void> nsCursorClass,
    required Pointer<Void> setSelector,
    required Pointer<Void> respondsSelector,
    required Pointer<Void> northWestSouthEastSelector,
    required Pointer<Void> northEastSouthWestSelector,
  })  : _msgSendId = msgSendId,
        _msgSendVoid = msgSendVoid,
        _msgSendBool = msgSendBool,
        _nsCursorClass = nsCursorClass,
        _setSelector = setSelector,
        _respondsSelector = respondsSelector,
        _northWestSouthEastSelector = northWestSouthEastSelector,
        _northEastSouthWestSelector = northEastSouthWestSelector;

  final _MsgSendIdDart _msgSendId;
  final _MsgSendVoidDart _msgSendVoid;
  final _MsgSendBoolDart _msgSendBool;
  final Pointer<Void> _nsCursorClass;
  final Pointer<Void> _setSelector;
  final Pointer<Void> _respondsSelector;
  final Pointer<Void> _northWestSouthEastSelector;
  final Pointer<Void> _northEastSouthWestSelector;

  static final _NsCursorBridge? instance = _create();

  static _NsCursorBridge? _create() {
    try {
      final DynamicLibrary process = DynamicLibrary.process();
      final _MallocDart malloc =
          process.lookupFunction<_MallocNative, _MallocDart>('malloc');
      final _FreeDart free =
          process.lookupFunction<_FreeNative, _FreeDart>('free');
      final _PtrFromCStrDart getClass = process
          .lookupFunction<_PtrFromCStrNative, _PtrFromCStrDart>('objc_getClass');
      final _PtrFromCStrDart selRegister =
          process.lookupFunction<_PtrFromCStrNative, _PtrFromCStrDart>(
              'sel_registerName');
      final _MsgSendIdDart msgSendId =
          process.lookupFunction<_MsgSendIdNative, _MsgSendIdDart>(
              'objc_msgSend');
      final _MsgSendVoidDart msgSendVoid =
          process.lookupFunction<_MsgSendVoidNative, _MsgSendVoidDart>(
              'objc_msgSend');
      final _MsgSendBoolDart msgSendBool =
          process.lookupFunction<_MsgSendBoolNative, _MsgSendBoolDart>(
              'objc_msgSend');

      // Turn an ASCII string into a freshly malloc'd, NUL-terminated C string,
      // hand it to [resolve] (objc_getClass / sel_registerName, both of which
      // copy what they need), then free it — nothing is leaked.
      Pointer<Void> resolve(String name, _PtrFromCStrDart fn) {
        final Pointer<Uint8> cstr = malloc(name.length + 1);
        for (int i = 0; i < name.length; i++) {
          cstr[i] = name.codeUnitAt(i);
        }
        cstr[name.length] = 0;
        final Pointer<Void> result = fn(cstr);
        free(cstr);
        return result;
      }

      final Pointer<Void> nsCursorClass = resolve('NSCursor', getClass);
      if (nsCursorClass == nullptr) return null;

      return _NsCursorBridge._(
        msgSendId: msgSendId,
        msgSendVoid: msgSendVoid,
        msgSendBool: msgSendBool,
        nsCursorClass: nsCursorClass,
        setSelector: resolve('set', selRegister),
        respondsSelector: resolve('respondsToSelector:', selRegister),
        northWestSouthEastSelector:
            resolve('_windowResizeNorthWestSouthEastCursor', selRegister),
        northEastSouthWestSelector:
            resolve('_windowResizeNorthEastSouthWestCursor', selRegister),
      );
    } catch (_) {
      return null;
    }
  }

  /// Applies the diagonal cursor; `false` if the private selector is unavailable.
  bool setDiagonal(bool northEastSouthWest) {
    try {
      final Pointer<Void> selector = northEastSouthWest
          ? _northEastSouthWestSelector
          : _northWestSouthEastSelector;
      if (_msgSendBool(_nsCursorClass, _respondsSelector, selector) == 0) {
        return false;
      }
      final Pointer<Void> cursor = _msgSendId(_nsCursorClass, selector);
      if (cursor == nullptr) return false;
      _msgSendVoid(cursor, _setSelector); // [cursor set]
      return true;
    } catch (_) {
      return false;
    }
  }
}
