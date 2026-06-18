/// Resolves a single authored element into its resolved copy (spec 007b §4),
/// honoring the 007a §3 field-partition contract: same concrete type, same
/// id/bounds/style; only the data-bearing field changes. Text `expression`s are
/// evaluated; image `FieldImageSource`s become `BytesImageSource`; every other
/// type (shape, barcode, custom) passes through unchanged.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/data_row.dart';
import '../../domain/elements/barcode_element.dart';
import '../../domain/elements/image_element.dart';
import '../../domain/elements/image_source.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/report_element.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/format/apply_jet_format.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';
import 'fill_eval_context.dart';
import 'report_diagnostics.dart';

/// Resolves elements against a row + variables, recording diagnostics.
class ElementResolver {
  /// Creates a resolver sharing [diagnostics] and the [warnedFields] dedup set.
  ///
  /// In a **schema-aware** context the caller supplies [knownFields] (the names
  /// declared by the active data source). A text binding that references a field
  /// outside that set resolves to [unresolvedFieldToken] (013 / FR-007). When
  /// [knownFields] is null (a headless render with no declared schema) behavior
  /// is unchanged — a missing field resolves empty — so existing reports never
  /// regress (013 / SC-005).
  ElementResolver({
    required this.functions,
    required this.diagnostics,
    Set<String>? warnedFields,
    this.knownFields,
    this.unresolvedFieldToken = '#ERROR',
  }) : warnedFields = warnedFields ?? <String>{};

  /// The function registry for expression evaluation.
  final JetFunctionRegistry functions;

  /// The shared diagnostics sink.
  final ReportDiagnostics diagnostics;

  /// Shared missing-field dedup set.
  final Set<String> warnedFields;

  /// The field names declared by the active data source, or null when the
  /// render is not schema-aware (see the constructor).
  final Set<String>? knownFields;

  /// The text rendered for a binding to a field absent from [knownFields].
  /// Defaults to the literal `#ERROR`; the designer/preview pass a localized
  /// value so the render layer never imports l10n (Constitution II).
  final String unresolvedFieldToken;

  /// Image elements already diagnosed for a URL-only source, so a band that
  /// repeats per row warns once per element, not once per instance.
  final Set<String> _warnedUrlImages = <String>{};

  /// Returns the resolved copy of [element].
  ReportElement resolve(
    ReportElement element, {
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
  }) {
    if (element is BarcodeElement) {
      return _resolveBarcode(element, row);
    }
    if (element is TextElement && element.expression != null) {
      return _resolveText(element,
          row: row, params: params, variables: variables);
    }
    if (element is ImageElement && element.source is FieldImageSource) {
      return _resolveImage(element, row);
    }
    if (element is ImageElement && element.source is UrlImageSource) {
      // FR-012b/FR-015 (011): the library performs no I/O — a URL-only source
      // cannot resolve to bytes here, so the shared renderer draws a
      // placeholder and the host is told why.
      if (_warnedUrlImages.add(element.id)) {
        diagnostics.warning(
            'Image "${element.id}" has a URL-only source; the library '
            'performs no network I/O (supply bytes via the data source or '
            'embed them) — a placeholder renders',
            elementId: element.id);
      }
      return element;
    }
    return element;
  }

  TextElement _resolveText(
    TextElement el, {
    required DataRow? row,
    required Map<String, Object?> params,
    required Map<String, JetValue> variables,
  }) {
    final Set<String> pageRefs = <String>{};
    final FillEvalContext ctx = FillEvalContext(
      row: row,
      params: params,
      variables: variables,
      functions: functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
      pageRefs: pageRefs,
      elementId: el.id,
    );
    final Expression parsed;
    try {
      parsed = Expression.parse(el.expression!);
    } on ExpressionException catch (e) {
      diagnostics.error('Expression parse failed: ${e.message}',
          elementId: el.id);
      return TextElement(
          id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
    }
    // Schema-aware unresolved-binding check (013 / FR-007): a reference to a
    // field the data source does not declare renders the (localizable) token.
    final Set<String>? known = knownFields;
    if (known != null) {
      final List<String> missing = <String>[
        for (final String f in parsed.references.fields)
          if (!known.contains(f)) f,
      ];
      if (missing.isNotEmpty) {
        if (warnedFields.add(missing.first)) {
          diagnostics.warning(
              'Field(s) ${missing.join(', ')} are not in the data source',
              elementId: el.id);
        }
        return TextElement(
            id: el.id,
            bounds: el.bounds,
            text: unresolvedFieldToken,
            style: el.style);
      }
    }
    final JetValue value = parsed.evaluate(ctx);
    if (pageRefs.isNotEmpty) {
      diagnostics.error(
        'Page-scoped variable(s) ${pageRefs.join(', ')} are only allowed in '
        'page/column header/footer text elements',
        elementId: el.id,
      );
      // Preserve the authored text; clear the (illegal) expression.
      return TextElement(
          id: el.id, bounds: el.bounds, text: el.text, style: el.style);
    }
    if (value is JetError) {
      diagnostics.error('Expression error: ${value.message}', elementId: el.id);
    }
    // Apply the label's display format (013 / FR-011): a non-empty pattern that
    // does not fit the value's type, or is malformed, leaves the value unchanged
    // (FR-012) — never an error token.
    final String? format = el.format;
    final JetValue formatted = (format != null && format.isNotEmpty)
        ? applyJetFormat(value, format)
        : value;
    return TextElement(
        id: el.id,
        bounds: el.bounds,
        text: jetStringify(formatted),
        style: el.style);
  }

  ImageElement _resolveImage(ImageElement el, DataRow? row) {
    final String field = (el.source as FieldImageSource).field;
    if (row != null && row.hasField(field)) {
      final Object? value = row.field(field);
      // Defensively copy every byte form so the resolved element is an
      // independent snapshot, never aliasing the data source's buffer.
      if (value is Uint8List) {
        return _withBytes(el, Uint8List.fromList(value));
      }
      if (value is List<int>) {
        return _withBytes(el, Uint8List.fromList(value));
      }
      if (value is String) {
        try {
          return _withBytes(el, base64Decode(value));
        } on FormatException {
          diagnostics.warning(
              'Image field "$field" contains an invalid base64 string',
              elementId: el.id);
          return el;
        }
      }
    }
    diagnostics.warning('Image field "$field" did not resolve to bytes',
        elementId: el.id);
    return el;
  }

  ImageElement _withBytes(ImageElement el, Uint8List bytes) => ImageElement(
      id: el.id,
      bounds: el.bounds,
      source: BytesImageSource(bytes),
      fit: el.fit);

  BarcodeElement _resolveBarcode(BarcodeElement el, DataRow? row) {
    String value = el.data;
    final String? field = el.dataField;
    if (field != null) {
      final Set<String>? known = knownFields;
      if (known != null && !known.contains(field)) {
        if (warnedFields.add(field)) {
          diagnostics.warning('Field "$field" is not in the data source',
              elementId: el.id);
        }
        value = '';
      } else if (row != null && row.hasField(field)) {
        final Object? v = row.field(field);
        value = v?.toString() ?? '';
      } else {
        value = '';
      }
    }

    // Flatten the binding so the renderer sees a literal.
    return field == null ? el : el.copyWith(data: value, dataField: () => null);
  }
}
