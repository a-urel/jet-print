// Web stand-in for example_io.dart, so the example tests still compile in the
// Chrome bundle, which cannot load `example/`. Those tests are VM-only, so none
// of this runs; the signatures mirror the files under example/.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

Never _vmOnly() =>
    throw UnsupportedError('the package examples are tested on the VM only');

// example/jet_print_example.dart
ReportDefinition get greetingsReport => _vmOnly();
RenderedReport renderGreetings(List<String> names) => _vmOnly();
Future<Uint8List> exportGreetingsPdf(List<String> names) => _vmOnly();

class GreetingsApp extends StatelessWidget {
  const GreetingsApp({super.key, required this.report});

  final RenderedReport report;

  @override
  Widget build(BuildContext context) => _vmOnly();
}

// example/designer_example.dart
JetDataSchema get customerSchema => _vmOnly();
JetDataSource get customerRows => _vmOnly();
String saveReport(JetReportDesignerController controller) => _vmOnly();
void openReport(JetReportDesignerController controller, String json) =>
    _vmOnly();

class DesignerApp extends StatelessWidget {
  const DesignerApp({super.key});

  @override
  Widget build(BuildContext context) => _vmOnly();
}

// example/data_example.dart
JetDataSchema get salesSchema => _vmOnly();
JetDataSource get ordersFromJson => _vmOnly();
JetDataSource get ordersFromObjects => _vmOnly();
ReportDefinition get salesByRegion => _vmOnly();
RenderedReport renderSales(JetDataSource source) => _vmOnly();
