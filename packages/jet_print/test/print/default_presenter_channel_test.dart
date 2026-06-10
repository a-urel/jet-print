// Default-presenter channel protocol (012 — regression for the macOS print
// freeze).
//
// `Printing.layoutPdf` defaults to `dynamicLayout: true`, and the plugin's
// macOS implementation of dynamic mode hard-blocks the MAIN thread with a
// semaphore inside `knowsPageRange`, waiting for a Dart reply that can only
// be delivered on that same blocked main thread — a deadlock: the dialog
// never opens and the app freezes. Our document never reflows to the
// dialog's paper anyway (contract B6: the bytes ARE the artifact), so the
// default presenter MUST pass `dynamicLayout: false`. This test mocks the
// `net.nfet.printing` method channel and pins the flag plus the
// availability-check-then-print order.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/print/jet_report_printer.dart';

import '../rendering/export/support/export_fixtures.dart';

const MethodChannel _printingChannel = MethodChannel('net.nfet.printing');

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  /// Installs a fake platform for the printing plugin: answers
  /// `printingInfo`, captures `printPdf` arguments, and completes the job.
  Map<String, Object?> mockPrintingPlatform({required bool canPrint}) {
    final Map<String, Object?> captured = <String, Object?>{};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_printingChannel,
        (MethodCall call) async {
      switch (call.method) {
        case 'printingInfo':
          return <String, Object?>{'canPrint': canPrint};
        case 'printPdf':
          captured.addAll((call.arguments as Map<Object?, Object?>)
              .cast<String, Object?>());
          // The platform reports completion asynchronously via an inbound
          // `onCompleted` message; emulate it so layoutPdf's future resolves.
          final ByteData completed = const StandardMethodCodec()
              .encodeMethodCall(MethodCall('onCompleted', <String, Object?>{
            'job': captured['job'],
            'completed': true,
          }));
          binding.defaultBinaryMessenger.handlePlatformMessage(
              'net.nfet.printing', completed, (ByteData? _) {});
          return 1;
        default:
          return null;
      }
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_printingChannel, null));
    return captured;
  }

  test(
      'the default presenter passes dynamicLayout: false '
      '(macOS dynamic mode deadlocks the main thread)', () async {
    final Map<String, Object?> captured = mockPrintingPlatform(canPrint: true);
    final bool sent = await const JetReportPrinter()
        .printReport(textOnlyReport(PageFormat.a4Portrait));
    expect(sent, isTrue);
    expect(captured['dynamic'], isFalse,
        reason: 'dynamicLayout MUST stay false: the macOS plugin implements '
            'dynamic re-layout by blocking the main thread on a semaphore '
            'whose signal can only arrive on that same thread — the app '
            'freezes. The exported bytes never reflow to the dialog paper '
            'anyway (contract B6).');
    expect(captured['width'], closeTo(595.28, 0.01),
        reason: 'the dialog opens at the template\'s true page size');
    expect(captured['height'], closeTo(841.89, 0.01));
  });

  test('an unavailable platform throws BEFORE any printPdf call', () async {
    final Map<String, Object?> captured = mockPrintingPlatform(canPrint: false);
    await expectLater(
      const JetReportPrinter()
          .printReport(textOnlyReport(PageFormat.a4Portrait)),
      throwsA(isA<PrintUnavailableException>()),
    );
    expect(captured, isEmpty,
        reason: 'canPrint: false must short-circuit — no dialog attempt');
  });
}
