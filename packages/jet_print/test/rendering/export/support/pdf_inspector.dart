// test/rendering/export/support/pdf_inspector.dart
/// A minimal, dependency-free PDF reader for the export tests (012).
///
/// Understands exactly the subset `package:pdf` 3.12.0 emits at the low level:
/// classic (non-object-stream) bodies, direct `/Length` values, FlateDecode
/// stream filters, per-page `/MediaBox`, `/Kids` page trees, Type0 text drawn
/// as `BT … x y Td [<hex CIDs>]TJ ET`, `/ToUnicode` bfchar CMaps, and images
/// placed via `q w 0 0 h x y cm /Name Do Q`. Intentionally NOT a general PDF
/// parser — assertions on anything outside that subset should fail loudly.
library;

import 'dart:convert' show latin1;
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// One indirect PDF object: its serial, dict source, and (inflated) stream.
class PdfRawObject {
  PdfRawObject({required this.serial, required this.dict, this.stream});

  /// The object number (`N` in `N 0 obj`).
  final int serial;

  /// The dictionary region, as latin-1 text.
  final String dict;

  /// The stream payload, inflated when the dict declares FlateDecode.
  final Uint8List? stream;

  /// The stream as latin-1 text ('' when there is no stream).
  String get streamText =>
      stream == null ? '' : latin1.decode(stream!, allowInvalid: true);
}

/// An image draw: the `cm` rectangle (PDF user space, y up from bottom-left)
/// that a `/Name Do` was painted into.
class PdfImageDraw {
  const PdfImageDraw(
      {required this.width,
      required this.height,
      required this.x,
      required this.y});

  /// Drawn width, in points.
  final double width;

  /// Drawn height, in points.
  final double height;

  /// Left edge, in points.
  final double x;

  /// BOTTOM edge, in points (PDF origin is bottom-left).
  final double y;

  @override
  String toString() => 'PdfImageDraw(${width}x$height at $x,$y)';
}

/// A clip rectangle installed with `x y w h re W n`.
class PdfClipRect {
  const PdfClipRect(
      {required this.x,
      required this.y,
      required this.width,
      required this.height});

  /// Left edge, in points.
  final double x;

  /// BOTTOM edge, in points.
  final double y;

  /// Width, in points.
  final double width;

  /// Height, in points.
  final double height;

  @override
  String toString() => 'PdfClipRect($x,$y ${width}x$height)';
}

/// Parses [bytes] once and answers structural questions about the document.
class PdfInspector {
  PdfInspector(Uint8List bytes) {
    if (latin1.decode(bytes.sublist(0, 5)) != '%PDF-') {
      throw const FormatException('not a PDF: missing %PDF- header');
    }
    _parseObjects(bytes);
    _resolvePages();
    _parseCmaps();
  }

  static final ZLibCodec _zlib = ZLibCodec();

  /// Captures `N G obj`.
  static final RegExp _objHeader = RegExp(r'(\d+)\s+\d+\s+obj\b');
  static final RegExp _lengthRe = RegExp(r'/Length\s+(\d+)\b');
  static final RegExp _mediaBoxRe = RegExp(
      r'/MediaBox\s*\[\s*([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s*\]');
  static final RegExp _refRe = RegExp(r'(\d+)\s+\d+\s+R\b');
  static final RegExp _bfcharRe =
      RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>');
  static final RegExp _tjRe = RegExp(r'\[<([0-9A-Fa-f]*)>\]\s*TJ');
  static final RegExp _imageCmRe = RegExp(
      r'q\s+([\d.+-]+)\s+0\s+0\s+([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s+cm\s+/\w+\s+Do\s+Q');
  static final RegExp _clipRe =
      RegExp(r'([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s+re\s+W\s+n');

  final Map<int, PdfRawObject> _objects = <int, PdfRawObject>{};
  final List<int> _pageSerials = <int>[];
  final List<List<int>> _cmaps = <List<int>>[];
  String _pagesDict = '';

  /// Every parsed indirect object, by serial.
  Map<int, PdfRawObject> get objects => _objects;

  /// The number of pages in the `/Kids` tree, in document order.
  int get pageCount => _pageSerials.length;

  void _parseObjects(Uint8List bytes) {
    final String text = latin1.decode(bytes, allowInvalid: true);
    int cursor = 0;
    while (true) {
      final Match? header = _objHeader.matchAsPrefix(text, cursor) ??
          _firstMatchFrom(_objHeader, text, cursor);
      if (header == null) break;
      final int serial = int.parse(header.group(1)!);
      final int bodyStart = header.end;
      // The dict region is plain text; it ends at `stream` or `endobj`,
      // whichever comes first FOR THIS object.
      final int streamIdx = text.indexOf('stream', bodyStart);
      final int endobjIdx = text.indexOf('endobj', bodyStart);
      if (endobjIdx == -1) break; // malformed tail; stop scanning
      if (streamIdx != -1 && streamIdx < endobjIdx) {
        final String dict = text.substring(bodyStart, streamIdx);
        // Stream data begins after the EOL following the `stream` keyword.
        int dataStart = streamIdx + 'stream'.length;
        if (text.startsWith('\r\n', dataStart)) {
          dataStart += 2;
        } else if (text.startsWith('\n', dataStart)) {
          dataStart += 1;
        }
        final Match? len = _lengthRe.firstMatch(dict);
        final int dataEnd = len != null
            ? dataStart + int.parse(len.group(1)!)
            : text.indexOf('endstream', dataStart);
        Uint8List data = bytes.sublist(dataStart, dataEnd);
        if (dict.contains('FlateDecode')) {
          data = Uint8List.fromList(_zlib.decode(data));
        }
        _objects[serial] =
            PdfRawObject(serial: serial, dict: dict, stream: data);
        final int endobjAfter = text.indexOf('endobj', dataEnd);
        if (endobjAfter == -1) break;
        cursor = endobjAfter + 'endobj'.length;
      } else {
        _objects[serial] = PdfRawObject(
            serial: serial, dict: text.substring(bodyStart, endobjIdx));
        cursor = endobjIdx + 'endobj'.length;
      }
    }
  }

  static Match? _firstMatchFrom(RegExp re, String text, int from) {
    for (final Match m in re.allMatches(text, from)) {
      return m;
    }
    return null;
  }

  void _resolvePages() {
    for (final PdfRawObject obj in _objects.values) {
      if (obj.dict.contains('/Type/Pages') ||
          obj.dict.contains('/Type /Pages')) {
        _pagesDict = obj.dict;
        final int kidsIdx = obj.dict.indexOf('/Kids');
        if (kidsIdx == -1) continue;
        final int open = obj.dict.indexOf('[', kidsIdx);
        final int close = obj.dict.indexOf(']', open);
        for (final Match m
            in _refRe.allMatches(obj.dict.substring(open, close))) {
          _pageSerials.add(int.parse(m.group(1)!));
        }
      }
    }
  }

  void _parseCmaps() {
    for (final PdfRawObject obj in _objects.values) {
      final String s = obj.streamText;
      if (!s.contains('beginbfchar')) continue;
      // CID -> unicode rune, dense from 0 in dart_pdf's bfchar output.
      final Map<int, int> map = <int, int>{};
      for (final Match m in _bfcharRe.allMatches(s)) {
        map[int.parse(m.group(1)!, radix: 16)] =
            int.parse(m.group(2)!, radix: 16);
      }
      final List<int> dense = List<int>.generate(
          map.isEmpty ? 0 : map.keys.reduce((a, b) => a > b ? a : b) + 1,
          (int i) => map[i] ?? -1);
      _cmaps.add(dense);
    }
  }

  /// The `[x0 y0 x1 y1]` MediaBox of page [index] (page order), falling back
  /// to the `/Pages` node when the page itself declares none.
  List<double> mediaBoxOf(int index) {
    final PdfRawObject page = _objects[_pageSerials[index]]!;
    final Match? m =
        _mediaBoxRe.firstMatch(page.dict) ?? _mediaBoxRe.firstMatch(_pagesDict);
    if (m == null) {
      throw StateError('page $index has no MediaBox (nor the /Pages node)');
    }
    return <double>[
      for (int g = 1; g <= 4; g++) double.parse(m.group(g)!),
    ];
  }

  /// The concatenated (inflated) content streams of page [index], as text.
  String contentOf(int index) {
    final PdfRawObject page = _objects[_pageSerials[index]]!;
    final int idx = page.dict.indexOf('/Contents');
    if (idx == -1) return '';
    // `/Contents 4 0 R` or `/Contents[4 0 R 7 0 R]` — take refs up to the
    // next dict key so unrelated references are not swallowed.
    int end = page.dict.indexOf('/', idx + 1);
    if (end == -1) end = page.dict.length;
    final StringBuffer out = StringBuffer();
    for (final Match m in _refRe.allMatches(page.dict.substring(idx, end))) {
      out.write(_objects[int.parse(m.group(1)!)]?.streamText ?? '');
    }
    return out.toString();
  }

  /// Decodes every `[<hex>]TJ` text string on page [index] through every
  /// ToUnicode CMap in the document; a string is included when every CID
  /// resolves through that CMap (the wrong font's CMap yields gaps and is
  /// dropped). This mirrors how a viewer extracts/searches text (FR-004).
  Set<String> textOnPage(int index) {
    final Set<String> out = <String>{};
    for (final Match m in _tjRe.allMatches(contentOf(index))) {
      final String hex = m.group(1)!;
      for (final List<int> cmap in _cmaps) {
        final StringBuffer sb = StringBuffer();
        bool complete = hex.isNotEmpty;
        for (int i = 0; i + 4 <= hex.length; i += 4) {
          final int cid = int.parse(hex.substring(i, i + 4), radix: 16);
          if (cid <= 0 || cid >= cmap.length || cmap[cid] < 0) {
            complete = false;
            break;
          }
          sb.writeCharCode(cmap[cid]);
        }
        if (complete) out.add(sb.toString());
      }
    }
    return out;
  }

  /// Every extractable text string in the document.
  Set<String> get allText => <String>{
        for (int i = 0; i < pageCount; i++) ...textOnPage(i),
      };

  /// The number of DISTINCT embedded TrueType font programs: the set of
  /// objects referenced by `/FontFile2` (a program is referenced from both
  /// the descendant font dict and the FontDescriptor — count objects, not
  /// mentions).
  int get embeddedFontProgramCount {
    final RegExp ref = RegExp(r'/FontFile2\s+(\d+)\s+\d+\s+R');
    return <int>{
      for (final PdfRawObject o in _objects.values)
        for (final Match m in ref.allMatches(o.dict)) int.parse(m.group(1)!),
    }.length;
  }

  /// Whether page [index] draws text as text objects (`BT … TJ … ET`).
  bool hasTextObjectsOn(int index) {
    final String c = contentOf(index);
    return c.contains('BT ') && _tjRe.hasMatch(c) && c.contains('ET ');
  }

  /// The image draws on page [index], in paint order.
  List<PdfImageDraw> imageDrawsOn(int index) => <PdfImageDraw>[
        for (final Match m in _imageCmRe.allMatches(contentOf(index)))
          PdfImageDraw(
            width: double.parse(m.group(1)!),
            height: double.parse(m.group(2)!),
            x: double.parse(m.group(3)!),
            y: double.parse(m.group(4)!),
          ),
      ];

  /// The rectangular clips installed on page [index], in paint order.
  List<PdfClipRect> clipRectsOn(int index) => <PdfClipRect>[
        for (final Match m in _clipRe.allMatches(contentOf(index)))
          PdfClipRect(
            x: double.parse(m.group(1)!),
            y: double.parse(m.group(2)!),
            width: double.parse(m.group(3)!),
            height: double.parse(m.group(4)!),
          ),
      ];
}
