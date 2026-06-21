import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/popover_group.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('opening a member closes any other open member', () {
    final PopoverGroup group = PopoverGroup();
    final ShadPopoverController a = ShadPopoverController();
    final ShadPopoverController b = ShadPopoverController();
    group.add(a);
    group.add(b);

    a.show();
    expect(a.isOpen, isTrue);
    expect(b.isOpen, isFalse);

    b.show();
    expect(b.isOpen, isTrue);
    expect(a.isOpen, isFalse, reason: 'opening b evicts the open a');

    group.dispose();
    a.dispose();
    b.dispose();
  });

  test('a member can be closed without disturbing others', () {
    final PopoverGroup group = PopoverGroup();
    final ShadPopoverController a = ShadPopoverController();
    group.add(a);
    a.show();
    a.hide();
    expect(a.isOpen, isFalse);
    group.dispose();
    a.dispose();
  });

  test('a removed member no longer participates in eviction', () {
    final PopoverGroup group = PopoverGroup();
    final ShadPopoverController a = ShadPopoverController();
    final ShadPopoverController b = ShadPopoverController();
    group.add(a);
    group.add(b);
    group.remove(a);

    a.show();
    b.show();
    // b opened but a is no longer coordinated, so it stays as it was.
    expect(a.isOpen, isTrue);
    expect(b.isOpen, isTrue);

    group.dispose();
    a.dispose();
    b.dispose();
  });

  test('a controller outside any group is unaffected', () {
    final ShadPopoverController loner = ShadPopoverController();
    final PopoverGroup group = PopoverGroup();
    final ShadPopoverController member = ShadPopoverController();
    group.add(member);

    loner.show();
    member.show();
    expect(loner.isOpen, isTrue, reason: 'the loner is not in the group');
    expect(member.isOpen, isTrue);

    group.dispose();
    loner.dispose();
    member.dispose();
  });
}
