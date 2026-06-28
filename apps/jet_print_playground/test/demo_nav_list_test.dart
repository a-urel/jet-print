import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print_playground/demo_nav_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  const List<DemoNavItem> items = <DemoNavItem>[
    DemoNavItem(value: 'a', icon: LucideIcons.fileText, label: 'Alpha'),
    DemoNavItem(value: 'b', icon: LucideIcons.tag, label: 'Bravo'),
    DemoNavItem(value: 'c', icon: LucideIcons.package, label: 'Charlie'),
  ];

  Widget host({
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return ShadApp(
      home: Scaffold(
        body: SizedBox(
          width: 220,
          child: DemoNavList(
            items: items,
            selected: selected,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  testWidgets('renders one labeled tile per item', (WidgetTester tester) async {
    await tester.pumpWidget(host(selected: 'a', onSelect: (_) {}));
    for (final DemoNavItem item in items) {
      expect(find.text(item.label), findsOneWidget, reason: item.label);
    }
  });

  testWidgets('tapping a tile reports that item value',
      (WidgetTester tester) async {
    final List<String> taps = <String>[];
    await tester.pumpWidget(host(selected: 'a', onSelect: taps.add));
    await tester.tap(find.text('Bravo'));
    await tester.pumpAndSettle();
    expect(taps, <String>['b']);
  });

  testWidgets('the selected item uses a distinct (secondary) button',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(selected: 'b', onSelect: (_) {}));
    // The selected entry is the only filled `secondary` button; the rest are
    // ghost. shadcn exposes the variant on ShadButton.variant.
    final Iterable<ShadButton> buttons =
        tester.widgetList<ShadButton>(find.byType(ShadButton));
    final ShadButton selected = buttons
        .firstWhere((ShadButton b) => b.variant == ShadButtonVariant.secondary);
    expect((selected.child as Text).data, 'Bravo');
    expect(
        buttons
            .where((ShadButton b) => b.variant == ShadButtonVariant.ghost)
            .length,
        2,
        reason: 'the two unselected entries stay ghost');
  });
}
