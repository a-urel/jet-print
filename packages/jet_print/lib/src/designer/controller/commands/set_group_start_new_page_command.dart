/// The command that sets whether a report group starts each of its instances
/// (after the first) on a fresh page (023 — `ReportGroup.startNewPage`).
library;

import '../../../domain/report_group.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the `startNewPage` flag of the group named [group] to [value]. A no-op
/// (no history) when no group has that name, or when the flag already matches.
class SetGroupStartNewPageCommand extends EditCommand {
  /// Sets group [group]'s `startNewPage` to [value].
  const SetGroupStartNewPageCommand({
    required this.group,
    required this.value,
  });

  /// The name of the target group.
  final String group;

  /// The new `startNewPage` value.
  final bool value;

  @override
  String get label => 'Set group page break';

  @override
  DesignerDocument apply(DesignerDocument before) {
    final List<ReportGroup> groups =
        List<ReportGroup>.of(before.template.groups);
    bool changed = false;
    for (int i = 0; i < groups.length; i++) {
      final ReportGroup g = groups[i];
      if (g.name != group || g.startNewPage == value) continue;
      groups[i] = ReportGroup(
        name: g.name,
        expression: g.expression,
        keepTogether: g.keepTogether,
        reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
        startNewPage: value,
      );
      changed = true;
    }
    if (!changed) return before;
    return before.withTemplate(before.template.copyWith(groups: groups));
  }
}
