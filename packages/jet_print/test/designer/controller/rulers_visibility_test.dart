// Controller ruler-visibility flag (spec 014, Phase 2 / FR-017, C3.1).
//
// `rulersEnabled` is the single source of truth both the canvas (viewport inset)
// and the top bar (toggle `active`) read. It mirrors the existing
// `gridEnabled`/`setGridEnabled` pair exactly: default on, a real change
// notifies, a same-value set is a no-op (so the toggle never churns listeners).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  group('controller ruler visibility', () {
    test('defaults to on (FR-017)', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      expect(c.rulersEnabled, isTrue);
    });

    test('setRulersEnabled(false) flips it and notifies', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setRulersEnabled(false);

      expect(c.rulersEnabled, isFalse);
      expect(notifications, 1);
    });

    test('toggling back on flips it and notifies again', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      c.setRulersEnabled(false);
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setRulersEnabled(true);

      expect(c.rulersEnabled, isTrue);
      expect(notifications, 1);
    });

    test('setting the same value is a no-op (no notify)', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setRulersEnabled(true); // already true

      expect(c.rulersEnabled, isTrue);
      expect(notifications, 0);
    });

    test('is independent of grid/snap visibility', () {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);

      c.setRulersEnabled(false);

      expect(c.rulersEnabled, isFalse);
      expect(c.gridEnabled, isTrue, reason: 'rulers must not touch the grid');
      expect(c.snapEnabled, isTrue, reason: 'rulers must not touch snapping');
    });
  });

  // A non-listenable smoke check that the flag is exposed where ChangeNotifier
  // consumers expect it (the canvas/top-bar read it off the same controller).
  test('rulersEnabled is a plain bool getter on the ChangeNotifier', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    expect(c, isA<ChangeNotifier>());
    expect(c.rulersEnabled, isA<bool>());
  });
}
