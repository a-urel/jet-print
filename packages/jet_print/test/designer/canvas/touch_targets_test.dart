// Touch enlarges the resize-handle hit area to a finger-friendly target while
// the drawn handle (and thus goldens) stays put; a mouse keeps the 16px hit.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/designer/canvas/design_tunables.dart';
import 'package:jet_print/src/designer/canvas/selection_overlay.dart';
import 'package:jet_print/src/designer/designer_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('kHandleHitSizeTouch is a finger-friendly target larger than the mouse hit',
      () {
    expect(kHandleHitSizeTouch, greaterThanOrEqualTo(44));
    expect(kHandleHitSizeTouch, greaterThan(kHandleHitSize));
    // The visual size is unchanged — only the hit area grows.
    expect(kHandleVisualSize, 8);
  });

  testWidgets('the overlay sizes its handle hit box from touchTargets',
      (WidgetTester tester) async {
    // A handle Positioned is `hit` square; assert touch swaps 16 -> 44 while the
    // drawn handle box stays kHandleVisualSize. We read the Positioned that owns
    // a handle key by pumping the overlay twice (mouse, then touch).
    Future<double> hitSizeFor({required bool touch}) async {
      await tester.pumpWidget(_HostOverlay(touchTargets: touch));
      final Finder handle = find.byKey(handleKey(ResizeHandle.topLeft));
      final Size size = tester.getSize(handle);
      return size.width;
    }

    expect(await hitSizeFor(touch: false), kHandleHitSize);
    expect(await hitSizeFor(touch: true), kHandleHitSizeTouch);
  });
}

/// A minimal host that mounts [DesignerSelectionOverlay] with one element
/// selected, following the same harness pattern as band_bounded_chrome_test.
class _HostOverlay extends StatefulWidget {
  const _HostOverlay({required this.touchTargets});

  final bool touchTargets;

  @override
  State<_HostOverlay> createState() => _HostOverlayState();
}

class _HostOverlayState extends State<_HostOverlay> {
  final JetReportDesignerController _controller =
      JetReportDesignerController();

  @override
  void initState() {
    super.initState();
    // Create one element so the overlay has a single-element selection.
    final String bandId = _controller.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .id;
    _controller.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(20, 20));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DesignTimeLayout layout =
        DesignTimeLayout.of(_controller.definition);

    return ShadApp(
      themeMode: ThemeMode.light,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      home: DesignerScope(
        controller: _controller,
        child: SizedBox(
          width: 800,
          height: 600,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DesignerSelectionOverlay(
                  layout: layout,
                  scale: 1.0,
                  touchTargets: widget.touchTargets,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
