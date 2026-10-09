// A minimal jet_print report: describe it, fill it with data, then preview it
// in a widget or export it to PDF.
//
// The designer is one widget away: put `const JetReportDesigner()` inside the
// same ShadApp to let users edit the report instead of only viewing it.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 1. Describe the report: a title once, then one line per data row.
const ReportDefinition greetingsReport = ReportDefinition(
  name: 'Greetings',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    title: Band(
      id: 'title',
      type: BandType.title,
      height: 40,
      elements: <ReportElement>[
        TextElement(
          id: 'heading',
          bounds: JetRect(x: 0, y: 0, width: 300, height: 28),
          text: 'Greetings',
          style: JetTextStyle(fontSize: 20, weight: JetFontWeight.bold),
        ),
      ],
    ),
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 24,
          elements: <ReportElement>[
            TextElement(
              id: 'greeting',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 20),
              text: '', // replaced per row by the expression
              expression: r'"Hello, " + $F{name} + "!"',
            ),
          ],
        )),
      ],
    ),
  ),
);

/// 2. Fill it with data. Pages are laid out lazily, as they are read.
RenderedReport renderGreetings(List<String> names) =>
    const JetReportEngine().renderDefinition(
      greetingsReport,
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (final String name in names) <String, Object?>{'name': name},
      ]),
    );

/// 3a. Export it headlessly: you own the bytes.
Future<Uint8List> exportGreetingsPdf(List<String> names) =>
    const JetReportExporter().toPdf(renderGreetings(names));

/// 3b. Or preview it. The preview reads the ambient shadcn_ui theme and the
/// library's own localizations.
class GreetingsApp extends StatelessWidget {
  /// Creates an app that previews [report].
  const GreetingsApp({super.key, required this.report});

  /// The filled report to preview.
  final RenderedReport report;

  @override
  Widget build(BuildContext context) => ShadApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          JetPrintLocalizations.delegate,
        ],
        supportedLocales: JetPrintLocalizations.supportedLocales,
        home: JetReportPreview(report: report),
      );
}

void main() {
  runApp(GreetingsApp(
    report: renderGreetings(const <String>['Ada', 'Grace', 'Linus']),
  ));
}
