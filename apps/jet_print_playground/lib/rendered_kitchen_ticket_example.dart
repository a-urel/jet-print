/// Renders the kitchen-ticket sample through the public engine — the consumer
/// side of the roll-paper demo, all through `package:jet_print/jet_print.dart`
/// only.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'kitchen_ticket_sample.dart';

/// The sample order as an in-memory data source typed by
/// [kitchenTicketSchema].
JetDataSource kitchenTicketDataSource() =>
    JetInMemoryDataSource(kitchenTicketData(),
        fields: kitchenTicketSchema.fields);

/// Renders [kitchenTicketDefinition] over [kitchenTicketDataSource] through
/// the native [JetReportEngine.renderDefinition] path — the same single call
/// the designer tab's preview uses. [definition] defaults to the bundled
/// sample so the designer can pass its LIVE edits; [source] defaults to the
/// sample data. The known fields are left to the source, which declares its
/// own schema, so an alternate source's fields resolve too.
RenderedReport renderKitchenTicketDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? kitchenTicketDefinition(),
      source ?? kitchenTicketDataSource(),
      options: RenderOptions(
        locale: const Locale('tr'),
        fonts: fonts,
      ),
    );
