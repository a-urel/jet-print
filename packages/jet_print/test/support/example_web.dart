// Web stand-in for example_io.dart, so test/example_test.dart still compiles in
// the Chrome bundle, which cannot load `example/`. The test is VM-only, so
// none of this runs; the signatures mirror example/jet_print_example.dart.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

RenderedReport renderGreetings(List<String> names) =>
    throw UnsupportedError('the package example is tested on the VM only');

Future<Uint8List> exportGreetingsPdf(List<String> names) =>
    throw UnsupportedError('the package example is tested on the VM only');

class GreetingsApp extends StatelessWidget {
  const GreetingsApp({super.key, required this.report});

  final RenderedReport report;

  @override
  Widget build(BuildContext context) =>
      throw UnsupportedError('the package example is tested on the VM only');
}
