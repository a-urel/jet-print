// Drag-and-drop and the canvas context menu.
part of '../design_canvas.dart';

extension _CanvasDropMenu on _DesignCanvasState {
  void _handleDrop(
    DesignerToolType type,
    Offset globalOffset,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final RenderObject? object = _pageKey.currentContext?.findRenderObject();
    if (object is! RenderBox) return;
    final Offset local = object.globalToLocal(globalOffset);
    final JetOffset page =
        JetOffset(local.dx / transform.scale, local.dy / transform.scale);
    final String? bandId = layout.bandIdNear(page);
    if (bandId == null) return;
    controller.createElement(
      type,
      bandId: bandId,
      at: layout.toBandLocal(bandId, page),
    );
  }

  /// Drops a field dragged from the Data Source panel, creating a text element
  /// bound to `$F{fieldName}` at the drop point (US2 / FR-011). Same coordinate
  /// math as [_handleDrop]; a drop outside any band is ignored.
  void _handleFieldDrop(
    FieldDragData data,
    Offset globalOffset,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final RenderObject? object = _pageKey.currentContext?.findRenderObject();
    if (object is! RenderBox) return;
    final Offset local = object.globalToLocal(globalOffset);
    final JetOffset page =
        JetOffset(local.dx / transform.scale, local.dy / transform.scale);
    final String? bandId = layout.bandIdNear(page);
    if (bandId == null) return;
    if (data.isCollection) {
      // A collection nests under the scope that owns the drop band (furniture /
      // once-bands resolve to the root master scope).
      final DetailScope? enclosing =
          findScopeOfBand(controller.definition, bandId);
      controller.createListWithBand(
        enclosing?.id ?? controller.definition.body.root.id,
        collectionField: data.fieldName,
      );
      return;
    }
    controller.createBoundElement(
      bandId: bandId,
      at: layout.toBandLocal(bandId, page),
      expression: '\$F{${data.fieldName}}',
    );
  }

  /// The canvas right-click menu: Cut / Copy / Paste / — / Duplicate / Delete,
  /// built from the same `ShadContextMenuItem` the Arrange menu uses (FR-002).
  /// Cut/Copy/Duplicate/Delete enable on [JetReportDesignerController.canCopy]
  /// and Paste on `canPaste` — the same predicates the toolbar reads, so the two
  /// surfaces cannot diverge (FR-005a, FR-012). Each item invokes the matching
  /// controller op and the menu closes on tap (FR-003, FR-011). The trailing
  /// shortcut hint reuses the platform glyph helper (⌘/Ctrl+); Delete has no
  /// modifier, so it carries no trailing glyph (FR-014a).
  List<Widget> _contextMenuItems(
    JetReportDesignerController controller,
    JetPrintLocalizations l10n,
  ) {
    ShadContextMenuItem item(
      String id,
      IconData icon,
      String label,
      String shortcutLetter, {
      required bool enabled,
      required VoidCallback op,
    }) {
      final String hint = shortcutHint(shortcutLetter);
      return ShadContextMenuItem(
        key: ValueKey<String>('jet_print.designer.menu.$id'),
        enabled: enabled,
        leading: Icon(icon, size: 16),
        trailing: hint.isEmpty ? null : Text(hint),
        onPressed: op,
        child: Text(label),
      );
    }

    final bool canCopy = controller.canCopy;
    return <Widget>[
      item('cut', LucideIcons.scissors, l10n.actionCutTooltip, 'X',
          enabled: canCopy, op: controller.cut),
      item('copy', LucideIcons.copy, l10n.actionCopyTooltip, 'C',
          enabled: canCopy, op: controller.copy),
      item('paste', LucideIcons.clipboard, l10n.actionPasteTooltip, 'V',
          enabled: controller.canPaste, op: controller.paste),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: ShadSeparator.horizontal(margin: EdgeInsets.zero),
      ),
      item('duplicate', LucideIcons.copyPlus, l10n.menuDuplicate, 'D',
          enabled: canCopy, op: controller.duplicate),
      item('delete', LucideIcons.trash2, l10n.menuDelete, '',
          enabled: canCopy, op: controller.delete),
    ];
  }
}
