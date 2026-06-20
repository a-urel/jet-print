import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  late JetReportDesignerController c;

  setUp(() => c = JetReportDesignerController());
  tearDown(() => c.dispose());

  test('the default fit mode is width', () {
    expect(c.viewFitMode, JetViewFitMode.width);
  });

  test('setViewFitMode sets the mode, bumps fitRequest, and notifies', () {
    int notifications = 0;
    c.addListener(() => notifications++);
    final int before = c.fitRequest;

    c.setViewFitMode(JetViewFitMode.page);

    expect(c.viewFitMode, JetViewFitMode.page);
    expect(c.fitRequest, before + 1);
    expect(notifications, greaterThan(0));
  });

  test('setZoomPercent sets the scale (clamped) and clears the fit mode', () {
    c.setViewFitMode(JetViewFitMode.page);

    c.setZoomPercent(130);
    expect(c.viewScale, closeTo(1.30, 1e-9));
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setZoomPercent(1000); // clamps to 400%
    expect(c.viewScale, 4.0);
    c.setZoomPercent(1); // clamps to 25%
    expect(c.viewScale, 0.25);
  });

  test('zoomIn, zoomOut, and zoomBy clear the fit mode', () {
    c.setViewFitMode(JetViewFitMode.width);
    c.zoomIn();
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setViewFitMode(JetViewFitMode.page);
    c.zoomOut();
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setViewFitMode(JetViewFitMode.width);
    c.zoomBy(1.1);
    expect(c.viewFitMode, JetViewFitMode.none);
  });

  test('zoomBy multiplies the current scale', () {
    c.setZoomPercent(100); // 1.0
    c.zoomBy(2.0);
    expect(c.viewScale, 2.0);
  });

  test('the low-level setViewScale leaves the fit mode untouched', () {
    c.setViewFitMode(JetViewFitMode.width);
    c.setViewScale(2.0); // the canvas applies a computed fit this way
    expect(c.viewFitMode, JetViewFitMode.width);
    expect(c.viewScale, 2.0);
  });

  test('clearing the mode notifies even when the scale does not change', () {
    c.setZoomPercent(100); // scale 1.0, mode none
    c.setViewFitMode(
        JetViewFitMode.width); // mode width (scale unchanged at 1.0)
    int notifications = 0;
    c.addListener(() => notifications++);

    c.setZoomPercent(100); // same scale (1.0) but must clear width -> none

    expect(c.viewFitMode, JetViewFitMode.none);
    expect(notifications, greaterThan(0));
  });

  test('fitToView is an alias for fit-width', () {
    final int before = c.fitRequest;
    c.setZoomPercent(50); // mode none
    c.fitToView();
    expect(c.viewFitMode, JetViewFitMode.width);
    expect(c.fitRequest, before + 1);
  });
}
