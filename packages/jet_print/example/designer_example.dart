// Hosting the designer: toolbox, canvas, inspector and a live preview in one
// widget, plus saving and reopening the design as JSON.
import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The fields the designer offers in its Data Source panel.
const JetDataSchema customerSchema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('name', type: JetFieldType.string),
    FieldDef('city', type: JetFieldType.string),
  ],
);

/// The rows the Preview tab fills the design with.
final JetDataSource customerRows = JetInMemoryDataSource(
  const <Map<String, Object?>>[
    <String, Object?>{'name': 'Ada', 'city': 'London'},
    <String, Object?>{'name': 'Grace', 'city': 'Arlington'},
  ],
);

/// The designer needs a shadcn_ui theme and the library's localizations.
class DesignerApp extends StatelessWidget {
  /// Creates the app shell around [ReportDesignerPage].
  const DesignerApp({super.key});

  @override
  Widget build(BuildContext context) => ShadApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          JetPrintLocalizations.delegate,
        ],
        supportedLocales: JetPrintLocalizations.supportedLocales,
        home: const ReportDesignerPage(),
      );
}

/// A full designer workspace over one controller.
class ReportDesignerPage extends StatefulWidget {
  /// Creates the page.
  const ReportDesignerPage({super.key});

  @override
  State<ReportDesignerPage> createState() => _ReportDesignerPageState();
}

class _ReportDesignerPageState extends State<ReportDesignerPage> {
  // The controller holds the design and its undo history.
  final JetReportDesignerController _controller = JetReportDesignerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JetReportWorkspace(
        controller: _controller,
        dataSchema: customerSchema,
        renderReport: (ReportDefinition definition) =>
            const JetReportEngine().renderDefinition(definition, customerRows),
      );
}

/// Saves the current design as versioned JSON.
String saveReport(JetReportDesignerController controller) =>
    JetReportFormat.encodeDefinitionJson(controller.definition);

/// Opens a saved design in the designer.
void openReport(JetReportDesignerController controller, String json) =>
    controller.open(JetReportFormat.decodeDefinitionJson(json));
