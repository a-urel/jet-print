/// Resolves a single authored element into its resolved copy (spec 007b §4),
/// honoring the 007a §3 field-partition contract: same concrete type, same
/// id/bounds/style; only the data-bearing field changes. Text `expression`s are
/// evaluated; image `FieldImageSource`s become `BytesImageSource`; every other
/// type (shape, barcode, custom) passes through unchanged.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/data_row.dart';
import '../../domain/elements/image_element.dart';
import '../../domain/elements/image_source.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/report_element.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';
import 'fill_eval_context.dart';
import 'report_diagnostics.dart';

/// Resolves elements against a row + variables, recording diagnostics.
class ElementResolver {
  /// Creates a resolver sharing [diagnostics] and the [warnedFields] dedup set.
  ElementResolver({
    required this.functions,
    required this.diagnostics,
    Set<String>? warnedFields,
  }) : warnedFields = warnedFields ?? <String>{};

  /// The function registry for expression evaluation.
  final JetFunctionRegistry functions;

  /// The shared diagnostics sink.
  final ReportDiagnostics diagnostics;

  /// Shared missing-field dedup set.
  final Set<String> warnedFields;

  /// Returns the resolved copy of [element].
  ReportElement resolve(
    ReportElement element, {
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
  }) {
    if (element is TextElement && element.expression != null) {
      return _resolveText(element, row: row, params: params, variables: variables);
    }
    if (element is ImageElement && element.source is FieldImageSource) {
      return _resolveImage(element, row);
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
    final JetValue value;
    try {
      value = Expression.parse(el.expression!).evaluate(ctx);
    } on ExpressionException catch (e) {
      diagnostics.error('Expression parse failed: ${e.message}', elementId: el.id);
      return TextElement(id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
    }
    if (pageRefs.isNotEmpty) {
      diagnostics.error(
        'Page-scoped variable(s) ${pageRefs.join(', ')} are only allowed in '
        'page/column header/footer text elements',
        elementId: el.id,
      );
      // Preserve the authored text; clear the (illegal) expression.
      return TextElement(id: el.id, bounds: el.bounds, text: el.text, style: el.style);
    }
    if (value is JetError) {
      diagnostics.error('Expression error: ${value.message}', elementId: el.id);
    }
    return TextElement(
        id: el.id, bounds: el.bounds, text: jetStringify(value), style: el.style);
  }

  ImageElement _resolveImage(ImageElement el, DataRow? row) {
    final String field = (el.source as FieldImageSource).field;
    final Uint8List? bytes = _bytesFromRow(row, field);
    if (bytes != null) {
      return ImageElement(
          id: el.id, bounds: el.bounds, source: BytesImageSource(bytes), fit: el.fit);
    }
    diagnostics.warning('Image field "$field" did not resolve to bytes',
        elementId: el.id);
    return el;
  }

  Uint8List? _bytesFromRow(DataRow? row, String field) {
    if (row == null || !row.hasField(field)) return null;
    final Object? v = row.field(field);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    if (v is String) {
      try {
        return base64Decode(v);
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
