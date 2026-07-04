/// The single source of an element's toolbox glyph, shared by the outline,
/// the properties header, and the palette — so a report object reads as the
/// same thing everywhere it appears (and a new element type gets its icon in
/// exactly one place).
library;

import 'package:flutter/widgets.dart' show IconData;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../domain/elements/barcode_element.dart';
import '../domain/elements/chart_element.dart';
import '../domain/elements/image_element.dart';
import '../domain/elements/shape_element.dart';
import '../domain/elements/text_element.dart';
import '../domain/report_element.dart';

/// The toolbox glyph for [element]; a safe square for unknown types.
IconData elementGlyph(ReportElement element) {
  if (element is TextElement) return LucideIcons.type;
  if (element is ShapeElement) return LucideIcons.square;
  if (element is ImageElement) return LucideIcons.image;
  if (element is BarcodeElement) return LucideIcons.barcode;
  if (element is ChartElement) return LucideIcons.chartBar;
  return LucideIcons.square;
}
