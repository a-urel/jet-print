/// Provides the attached data-source structure to the designer subtree (009).
library;

import 'package:flutter/widgets.dart';

import '../data/data_schema.dart';

/// An [InheritedWidget] that shares the host-supplied [JetDataSchema] (or null)
/// with the Data Source panel, the Properties binding editor, and the canvas, so
/// they can display the structure and resolve bindings against it.
///
/// Distinct from `DesignerScope` (which carries the mutable controller): the
/// schema is immutable per attachment, so a plain [InheritedWidget] suffices.
class DesignerSchemaScope extends InheritedWidget {
  /// Shares [dataSchema] (nullable — null means no source attached) and an
  /// optional [onSelectDataSource] action with [child].
  const DesignerSchemaScope({
    required this.dataSchema,
    this.onSelectDataSource,
    required super.child,
    super.key,
  });

  /// The attached data-source structure, or null when none is attached.
  final JetDataSchema? dataSchema;

  /// The guarded "select a data source" action, or null when the host wired
  /// none. Shown by the Data Source panel only when [dataSchema] is null.
  final VoidCallback? onSelectDataSource;

  /// The nearest attached schema above [context], or null if none is attached
  /// (or no scope is present). Subscribes the caller to changes.
  static JetDataSchema? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesignerSchemaScope>()
      ?.dataSchema;

  /// The nearest wired select-data-source action above [context], or null.
  static VoidCallback? selectCallbackOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesignerSchemaScope>()
      ?.onSelectDataSource;

  @override
  bool updateShouldNotify(DesignerSchemaScope oldWidget) =>
      oldWidget.dataSchema != dataSchema ||
      oldWidget.onSelectDataSource != onSelectDataSource;
}
