/// Commands: set a barcode element's data source (literal or bound field).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the literal [data] and clears any bound field.
class SetBarcodeDataCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeDataCommand({required this.id, required this.data});

  /// Target element id.
  final String id;

  /// Literal value to encode.
  final String data;

  @override
  String get label => 'Edit barcode data';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition,
            id,
            (ReportElement e) => e is BarcodeElement
                ? e.copyWith(data: data, dataField: () => null)
                : e),
      );
}

/// Binds the barcode value to [field] (or clears it to null → literal).
class SetBarcodeDataFieldCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeDataFieldCommand({required this.id, required this.field});

  /// Target element id.
  final String id;

  /// Field name, or null to clear the binding.
  final String? field;

  @override
  String get label => 'Edit barcode field';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition,
            id,
            (ReportElement e) =>
                e is BarcodeElement ? e.copyWith(dataField: () => field) : e),
      );
}
