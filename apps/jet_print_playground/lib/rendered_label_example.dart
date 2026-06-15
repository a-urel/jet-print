/// Real data for the label sample, plus the one-call render through the public
/// engine — the consumer side of the 3-column address-label demo, all through
/// `package:jet_print/jet_print.dart` only.
///
/// 100 synthetic addresses are generated deterministically (cycling fixed name/
/// street/city/country arrays — no RNG, so the output is stable) and then
/// **chunked into rows of three** to match [labelSchema]: each master record
/// carries three cells' worth of fields, prefixed `c0*`, `c1*`, `c2*`. The
/// last row holds a single filled cell (100 ÷ 3 = 33 full rows + 1), so its
/// `c1*`/`c2*` keys are absent and those tiles render blank.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'label_sample.dart';

/// How many flat address records the demo ships.
const int labelRecordCount = 100;

const List<String> _firstNames = <String>[
  'Anna', 'Ben', 'Carla', 'David', 'Elif', 'Felix', 'Greta', 'Hugo',
  'Ines', 'Jonas', 'Kira', 'Lars', 'Maya', 'Nils', 'Olga', 'Pavel',
  'Quinn', 'Rosa', 'Sven', 'Tara',
];

const List<String> _lastNames = <String>[
  'Becker', 'Costa', 'Dubois', 'Esposito', 'Fischer', 'García', 'Horvath',
  'Ivanov', 'Jansen', 'Kowalski', 'Lefèvre', 'Müller', 'Novak', 'Olsen',
  'Petrov', 'Rossi', 'Schmidt', 'Toth', 'Virtanen', 'Weber',
];

const List<String> _streets = <String>[
  'Lindenstraße 12', '14 Rue de la Paix', 'Via Roma 8', 'Calle Mayor 27',
  'Kerkstraat 4', 'Nyhavn 19', 'Mannerheimintie 5', 'Vasagatan 31',
  'Karl-Marx-Allee 90', 'Wenceslas Sq. 3',
];

/// Postal code + city, the second address line.
const List<String> _cities = <String>[
  '10115 Berlin', '75002 Paris', '00184 Rome', '28013 Madrid',
  '1012 Amsterdam', '1051 Copenhagen', '00100 Helsinki', '11120 Stockholm',
  '10243 Berlin', '11000 Prague',
];

const List<String> _countries = <String>[
  'Germany', 'France', 'Italy', 'Spain', 'Netherlands', 'Denmark',
  'Finland', 'Sweden', 'Germany', 'Czechia',
];

/// [labelRecordCount] flat address maps (`name`/`street`/`city`/`country`),
/// generated deterministically so the sample is reproducible.
List<Map<String, String>> _addresses() => <Map<String, String>>[
      for (int i = 0; i < labelRecordCount; i++)
        <String, String>{
          'name': '${_firstNames[i % _firstNames.length]} '
              '${_lastNames[(i * 7) % _lastNames.length]}',
          'street': _streets[i % _streets.length],
          'city': _cities[i % _cities.length],
          'country': _countries[i % _countries.length],
        },
    ];

/// Groups the flat [addresses] into rows of [labelColumns], emitting one master
/// map per row with each cell's fields prefixed `c{column}{Field}`. A trailing
/// partial row simply omits the missing cells' keys (they render blank).
List<Map<String, Object?>> chunkIntoRows(List<Map<String, String>> addresses) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (int start = 0; start < addresses.length; start += labelColumns) {
    final Map<String, Object?> row = <String, Object?>{};
    for (int col = 0; col < labelColumns; col++) {
      final int idx = start + col;
      if (idx >= addresses.length) break;
      final Map<String, String> a = addresses[idx];
      row['c${col}Name'] = a['name'];
      row['c${col}Street'] = a['street'];
      row['c${col}City'] = a['city'];
      row['c${col}Country'] = a['country'];
    }
    rows.add(row);
  }
  return rows;
}

/// The chunked label rows as an in-memory data source, matching [labelSchema].
JetDataSource labelDataSource() =>
    JetInMemoryDataSource(chunkIntoRows(_addresses()));

/// Renders [labelSampleDefinition] over [labelDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderLabelDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? labelSampleDefinition(),
      source ?? labelDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: <String>{
          for (final FieldDef f in labelSchema.fields) f.name,
        },
        fonts: fonts,
      ),
    );
