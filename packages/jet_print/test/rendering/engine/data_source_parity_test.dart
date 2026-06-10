// Data-source parity (011 — contract C8 / SC-006 / FR-011): the same logical
// dataset — including a nested collection — supplied via the in-memory, JSON,
// and object-backed sources yields BYTE-IDENTICAL rendered output, and
// host-supplied parameter values resolve in expressions.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/data/json_data_source.dart';
import 'package:jet_print/src/data/object_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const PageFormat _page =
    PageFormat(width: 400, height: 600, margins: JetEdgeInsets.all(10));

ReportTemplate _template() => const ReportTemplate(
      name: 'parity',
      page: _page,
      bands: <ReportBand>[
        // Master scope: an invoice header plus a parameter binding.
        ReportBand(
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 'customer',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
              text: 'customer',
              expression: r'$F{customer}',
            ),
            TextElement(
              id: 'by',
              bounds: JetRect(x: 0, y: 20, width: 200, height: 16),
              text: 'by',
              expression: r'"Printed by " + $P{printedBy}',
            ),
          ],
        ),
        // Child scope: the nested lines collection.
        ReportBand(
          type: BandType.detail,
          height: 20,
          collectionField: 'lines',
          elements: <ReportElement>[
            TextElement(
              id: 'line',
              bounds: JetRect(x: 0, y: 0, width: 360, height: 16),
              text: 'line',
              expression: r'$F{desc} + " x " + $F{qty}',
            ),
          ],
        ),
      ],
    );

/// The one logical dataset all three sources must represent identically.
const List<Map<String, Object?>> _rows = <Map<String, Object?>>[
  <String, Object?>{
    'customer': 'Acme GmbH',
    'lines': <Map<String, Object?>>[
      <String, Object?>{'desc': 'Widget', 'qty': 3},
      <String, Object?>{'desc': 'Gadget', 'qty': 1},
    ],
  },
  <String, Object?>{
    'customer': 'Globex Corp',
    'lines': <Map<String, Object?>>[
      <String, Object?>{'desc': 'Sprocket', 'qty': 7},
    ],
  },
];

/// An explicit schema shared by every variant, so inference differences can
/// never mask (or cause) an output difference.
const List<FieldDef> _schema = <FieldDef>[
  FieldDef('customer', type: JetFieldType.string),
  FieldDef(
    'lines',
    type: JetFieldType.collection,
    fields: <FieldDef>[
      FieldDef('desc', type: JetFieldType.string),
      FieldDef('qty', type: JetFieldType.integer),
    ],
  ),
];

class _Invoice {
  const _Invoice(this.customer, this.lines);

  final String customer;
  final List<Map<String, Object?>> lines;
}

RenderedReport _render(JetDataSource source) =>
    const JetReportEngine().render(
      _template(),
      source,
      options: const RenderOptions(
        parameters: <String, Object?>{'printedBy': 'A. Urel'},
      ),
    );

void main() {
  test('in-memory == JSON == object-backed, incl. a nested collection '
      '(SC-006)', () {
    final RenderedReport inMemory =
        _render(JetInMemoryDataSource(_rows, fields: _schema));

    final RenderedReport json = _render(JetJsonDataSource.parse(
      '[{"customer":"Acme GmbH","lines":[{"desc":"Widget","qty":3},'
      '{"desc":"Gadget","qty":1}]},'
      '{"customer":"Globex Corp","lines":[{"desc":"Sprocket","qty":7}]}]',
      fields: _schema,
    ));

    final RenderedReport objects = _render(JetObjectDataSource<_Invoice>(
      const <_Invoice>[
        _Invoice('Acme GmbH', <Map<String, Object?>>[
          <String, Object?>{'desc': 'Widget', 'qty': 3},
          <String, Object?>{'desc': 'Gadget', 'qty': 1},
        ]),
        _Invoice('Globex Corp', <Map<String, Object?>>[
          <String, Object?>{'desc': 'Sprocket', 'qty': 7},
        ]),
      ],
      fields: _schema,
      row: (_Invoice i) => <String, Object?>{
        'customer': i.customer,
        'lines': i.lines,
      },
    ));

    expect(inMemory.pageCount, json.pageCount);
    expect(inMemory.pageCount, objects.pageCount);
    for (int i = 0; i < inMemory.pageCount; i++) {
      expect(json.pageAt(i).frame, inMemory.pageAt(i).frame,
          reason: 'JSON page $i must equal in-memory byte-for-byte');
      expect(objects.pageAt(i).frame, inMemory.pageAt(i).frame,
          reason: 'object-backed page $i must equal in-memory byte-for-byte');
    }
  });

  test('parameter values supplied as a map resolve in expressions', () {
    final RenderedReport report =
        _render(JetInMemoryDataSource(_rows, fields: _schema));
    final List<String> runs = <String>[
      for (final TextRunPrimitive p in report
          .pageAt(0)
          .frame
          .primitives
          .whereType<TextRunPrimitive>())
        p.lines.map((TextLine l) => l.text).join(),
    ];
    expect(runs, contains('Printed by A. Urel'));
  });
}
