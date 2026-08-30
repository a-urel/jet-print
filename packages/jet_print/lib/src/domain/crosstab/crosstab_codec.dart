/// JSON for the crosstab model (spec A). Defaults are omitted, so a crosstab-free
/// report is byte-identical to one written before crosstabs existed and a minimal
/// crosstab stays small.
library;

import '../bool_property.dart';
import '../report_variable.dart' show JetCalculation;
import '../styles/box_style.dart';
import '../styles/text_style.dart';
import 'crosstab.dart';
import 'crosstab_group.dart';
import 'crosstab_measure.dart';
import 'crosstab_style.dart';

const CrosstabStyle _defaultStyle = CrosstabStyle();

/// Encodes [ct] to a JSON-safe map.
Map<String, Object?> encodeCrosstab(Crosstab ct) => <String, Object?>{
      'id': ct.id,
      if (ct.name != null) 'name': ct.name,
      if (ct.collectionField != null) 'collectionField': ct.collectionField,
      'rowGroups': <Object?>[
        for (final CrosstabGroup g in ct.rowGroups) _group(g)
      ],
      'columnGroups': <Object?>[
        for (final CrosstabGroup g in ct.columnGroups) _group(g),
      ],
      'measures': <Object?>[
        for (final CrosstabMeasure m in ct.measures) _measure(m),
      ],
      if (ct.style != _defaultStyle) 'style': _style(ct.style),
      if (ct.visible != const BoolProperty()) 'visible': ct.visible.toJson(),
    };

/// Reads a [Crosstab] from its [encodeCrosstab] map.
Crosstab decodeCrosstab(Map<String, Object?> json) => Crosstab(
      id: json['id']! as String,
      name: json['name'] as String?,
      collectionField: json['collectionField'] as String?,
      rowGroups: <CrosstabGroup>[
        for (final Object? g in json['rowGroups']! as List<Object?>)
          _readGroup((g! as Map).cast<String, Object?>()),
      ],
      columnGroups: <CrosstabGroup>[
        for (final Object? g in json['columnGroups']! as List<Object?>)
          _readGroup((g! as Map).cast<String, Object?>()),
      ],
      measures: <CrosstabMeasure>[
        for (final Object? m in json['measures']! as List<Object?>)
          _readMeasure((m! as Map).cast<String, Object?>()),
      ],
      style: json['style'] == null
          ? const CrosstabStyle()
          : _readStyle((json['style']! as Map).cast<String, Object?>()),
      visible: json['visible'] == null
          ? const BoolProperty()
          : BoolProperty.fromJson(
              (json['visible']! as Map).cast<String, Object?>()),
    );

Map<String, Object?> _group(CrosstabGroup g) => <String, Object?>{
      'id': g.id,
      'name': g.name,
      'expression': g.expression,
      if (g.sort != CrosstabSort.ascending) 'sort': g.sort.name,
      if (!g.showTotal) 'showTotal': false,
      if (g.totalLabel != null) 'totalLabel': g.totalLabel,
    };

CrosstabGroup _readGroup(Map<String, Object?> j) => CrosstabGroup(
      id: j['id']! as String,
      name: j['name']! as String,
      expression: j['expression']! as String,
      sort: j['sort'] == null
          ? CrosstabSort.ascending
          : CrosstabSort.values.byName(j['sort']! as String),
      showTotal: j['showTotal'] as bool? ?? true,
      totalLabel: j['totalLabel'] as String?,
    );

Map<String, Object?> _measure(CrosstabMeasure m) => <String, Object?>{
      'id': m.id,
      'name': m.name,
      'expression': m.expression,
      'aggregate': m.aggregate.name,
      if (m.format != null) 'format': m.format,
      if (m.cellTextStyle != null) 'cellTextStyle': m.cellTextStyle!.toJson(),
      if (m.cellBoxStyle != null) 'cellBoxStyle': m.cellBoxStyle!.toJson(),
    };

CrosstabMeasure _readMeasure(Map<String, Object?> j) => CrosstabMeasure(
      id: j['id']! as String,
      name: j['name']! as String,
      expression: j['expression']! as String,
      aggregate: JetCalculation.values.byName(j['aggregate']! as String),
      format: j['format'] as String?,
      cellTextStyle: j['cellTextStyle'] == null
          ? null
          : JetTextStyle.fromJson(
              (j['cellTextStyle']! as Map).cast<String, Object?>()),
      cellBoxStyle: j['cellBoxStyle'] == null
          ? null
          : JetBoxStyle.fromJson(
              (j['cellBoxStyle']! as Map).cast<String, Object?>()),
    );

Map<String, Object?> _style(CrosstabStyle s) => <String, Object?>{
      if (s.headerText != null) 'headerText': s.headerText!.toJson(),
      if (s.headerBox != null) 'headerBox': s.headerBox!.toJson(),
      if (s.cellText != null) 'cellText': s.cellText!.toJson(),
      if (s.cellBox != null) 'cellBox': s.cellBox!.toJson(),
      if (s.totalText != null) 'totalText': s.totalText!.toJson(),
      if (s.totalBox != null) 'totalBox': s.totalBox!.toJson(),
      if (s.rowLabelWidth != _defaultStyle.rowLabelWidth)
        'rowLabelWidth': s.rowLabelWidth,
      if (s.rowLabelIndent != _defaultStyle.rowLabelIndent)
        'rowLabelIndent': s.rowLabelIndent,
      if (s.measureColumnWidth != _defaultStyle.measureColumnWidth)
        'measureColumnWidth': s.measureColumnWidth,
      if (s.rowHeight != _defaultStyle.rowHeight) 'rowHeight': s.rowHeight,
      if (s.headerRowHeight != _defaultStyle.headerRowHeight)
        'headerRowHeight': s.headerRowHeight,
    };

CrosstabStyle _readStyle(Map<String, Object?> j) {
  JetTextStyle? text(String k) => j[k] == null
      ? null
      : JetTextStyle.fromJson((j[k]! as Map).cast<String, Object?>());
  JetBoxStyle? box(String k) => j[k] == null
      ? null
      : JetBoxStyle.fromJson((j[k]! as Map).cast<String, Object?>());
  double num_(String k, double fallback) =>
      (j[k] as num?)?.toDouble() ?? fallback;
  return CrosstabStyle(
    headerText: text('headerText'),
    headerBox: box('headerBox'),
    cellText: text('cellText'),
    cellBox: box('cellBox'),
    totalText: text('totalText'),
    totalBox: box('totalBox'),
    rowLabelWidth: num_('rowLabelWidth', _defaultStyle.rowLabelWidth),
    rowLabelIndent: num_('rowLabelIndent', _defaultStyle.rowLabelIndent),
    measureColumnWidth:
        num_('measureColumnWidth', _defaultStyle.measureColumnWidth),
    rowHeight: num_('rowHeight', _defaultStyle.rowHeight),
    headerRowHeight: num_('headerRowHeight', _defaultStyle.headerRowHeight),
  );
}
