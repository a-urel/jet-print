// Shared font-byte fixtures for the host-font tests (022 / T001).
//
// Real, parseable TTF bytes (so `JetFontFamily` validation and the registry's
// metrics parse succeed) plus deliberately-bad samples for the rejection
// tests. The valid faces are a Noto Serif Latin subset embedded in
// `fixture_font_data.dart` — distinct metrics from the bundled Default, so a
// host family built from them renders visibly differently than the default
// (the lever the cross-path golden leans on). These faces are test-only; they
// are not shipped in the library.
//
// Public-only consumer tests reach these fixtures through a relative import of
// this file — never through a `package:jet_print/src/...` path of their own.
library;

import 'dart:typed_data';

import 'fixture_font_data.dart';

/// A valid regular-weight, upright TTF face (Noto Serif subset).
Uint8List validRegularFontBytes() => kFixtureRegularFontBytes;

/// A valid bold, upright TTF face (Noto Serif subset).
Uint8List validBoldFontBytes() => kFixtureBoldFontBytes;

/// A valid regular-weight, italic TTF face (Noto Serif subset).
Uint8List validItalicFontBytes() => kFixtureItalicFontBytes;

/// Empty bytes — too short to be a TTF offset table; rejected at validation.
Uint8List emptyFontBytes() => Uint8List(0);

/// Bytes that are not a TTF program at all; rejected at validation.
Uint8List malformedFontBytes() =>
    Uint8List.fromList(<int>[0x4e, 0x4f, 0x50, 0x45, 0x00, 0x01, 0x02, 0x03]);
