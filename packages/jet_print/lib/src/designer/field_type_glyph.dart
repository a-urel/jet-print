/// The icon that signals a schema field's [JetFieldType] at a glance, shared by
/// every place a field is shown (the Data Source tree and the Properties value
/// picker) so the same field reads identically wherever it appears.
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/field_def.dart';

/// The glyph for [type] — string → text, integer → hash, double → calculator,
/// boolean → toggle, dateTime → calendar/clock, collection → list, and an
/// unknown/empty column → a help mark.
IconData fieldTypeGlyph(JetFieldType type) => switch (type) {
      JetFieldType.string => LucideIcons.type,
      JetFieldType.integer => LucideIcons.hash,
      JetFieldType.double => LucideIcons.calculator,
      JetFieldType.boolean => LucideIcons.toggleLeft,
      JetFieldType.dateTime => LucideIcons.calendarClock,
      JetFieldType.collection => LucideIcons.list,
      JetFieldType.unknown => LucideIcons.circleHelp,
    };
