// Double-tap → Properties focus: the controller carries an ephemeral one-shot
// UI intent (a flag, not a counter, so it survives until the panel that must
// consume it mounts — e.g. the narrow-layout overlay opening first).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('requestPropertiesFocus raises the pending flag and notifies', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    expect(c.pendingPropertiesFocus, isFalse);
    c.requestPropertiesFocus();
    expect(c.pendingPropertiesFocus, isTrue);
    expect(notifications, 1);
  });

  test('takePropertiesFocus consumes the flag once, without notifying', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    expect(c.takePropertiesFocus(), isFalse); // nothing pending
    c.requestPropertiesFocus();
    expect(c.takePropertiesFocus(), isTrue); // consume
    expect(c.takePropertiesFocus(), isFalse); // one-shot
    expect(c.pendingPropertiesFocus, isFalse);
    expect(notifications, 1); // only the request notified, not the take
  });

  test('a second request while one is pending still notifies listeners', () {
    // The shell/right panel react per-notification; a double-tap while a prior
    // request is somehow unconsumed must still bring the panel forward.
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    int notifications = 0;
    c.addListener(() => notifications++);

    c.requestPropertiesFocus();
    c.requestPropertiesFocus();
    expect(notifications, 2);
    expect(c.pendingPropertiesFocus, isTrue);
  });

  test('open() clears a pending request — it must not outlive its document',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.requestPropertiesFocus();
    c.open(c.definition);
    expect(c.pendingPropertiesFocus, isFalse);
    expect(c.takePropertiesFocus(), isFalse);
  });
}
