/// Commands: set a barcode element's data source (literal or bound field).
library;

import '../../../domain/elements/barcode_element.dart';
import '../element_edit_command.dart';

/// Sets the literal [data] and clears any bound field.
class SetBarcodeDataCommand extends ElementEditCommand<BarcodeElement> {
  /// Creates the command.
  const SetBarcodeDataCommand({required String id, required this.data})
      : super(id);

  /// Literal value to encode.
  final String data;

  @override
  String get label => 'Edit barcode data';

  @override
  BarcodeElement edit(BarcodeElement element) =>
      element.copyWith(data: data, dataField: () => null);
}

/// Binds the barcode value to [field] (or clears it to null → literal).
class SetBarcodeDataFieldCommand extends ElementEditCommand<BarcodeElement> {
  /// Creates the command.
  const SetBarcodeDataFieldCommand({required String id, required this.field})
      : super(id);

  /// Field name, or null to clear the binding.
  final String? field;

  @override
  String get label => 'Edit barcode field';

  @override
  BarcodeElement edit(BarcodeElement element) =>
      element.copyWith(dataField: () => field);
}
