// Properties header rename test (Task 7).
//
// Verifies that tapping the Properties panel header switches it to an
// EditableLabel, entering a name and submitting commits the rename to the
// controller, and the header reflects the new name.
//
// Drives the public `JetReportDesigner` only (Properties reached via its tab).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
final Finder _header =
    find.byKey(const ValueKey<String>('$_p.header'));

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// A minimal definition with one TextElement whose text is 'Subtotal' and no
/// name, so the header falls back to the text.
JetReportDesignerController _subtotalController() =>
    JetReportDesignerController(
      definition: ReportDefinition(
        name: 'Test',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 120,
                elements: <ReportElement>[
                  TextElement(
                    id: 'sub',
                    bounds: const JetRect(x: 10, y: 10, width: 160, height: 24),
                    text: 'Subtotal',
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'header shows fallback text and allows rename via tap',
    (WidgetTester tester) async {
      final JetReportDesignerController c = _subtotalController();
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);

      // Select the element.
      c.select('sub');
      await tester.pumpAndSettle();

      // 1. Header shows 'Subtotal' (the text fallback, element has no name).
      // Scope to the header widget to avoid matching the value field.
      expect(
        find.descendant(of: _header, matching: find.text('Subtotal')),
        findsOneWidget,
      );

      // 2. Tap the header to start editing.
      await tester.tap(_header);
      await tester.pumpAndSettle();

      // 3. The inline text field should now be present. Clear it and type 'Totals row'.
      final Finder editField =
          find.descendant(of: _header, matching: find.byType(EditableText));
      expect(editField, findsOneWidget);

      await tester.enterText(editField, 'Totals row');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 4. Element now has name 'Totals row'.
      final ReportElement updated = c.definition.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .first;
      expect(updated.name, 'Totals row');

      // 5. Header displays the new name.
      expect(
        find.descendant(of: _header, matching: find.text('Totals row')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'header edit resets when selection changes',
    (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: ReportDefinition(
          name: 'Test',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'detail',
                  type: BandType.detail,
                  height: 120,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'a',
                      bounds:
                          const JetRect(x: 10, y: 10, width: 100, height: 24),
                      text: 'Alpha',
                    ),
                    TextElement(
                      id: 'b',
                      bounds:
                          const JetRect(x: 10, y: 50, width: 100, height: 24),
                      text: 'Beta',
                    ),
                  ],
                )),
              ],
            ),
          ),
        ),
      );
      await pumpDesignerWith(tester, controller: c);
      await _openProperties(tester);

      c.select('a');
      await tester.pumpAndSettle();

      // Tap header to start editing 'a'.
      await tester.tap(_header);
      await tester.pumpAndSettle();

      // Verify editing field appears.
      expect(
        find.descendant(of: _header, matching: find.byType(EditableText)),
        findsOneWidget,
      );

      // Change selection to 'b' — editing flag should reset.
      c.select('b');
      await tester.pumpAndSettle();

      // Header shows 'Beta' (static text, not a text field any more).
      expect(
        find.descendant(of: _header, matching: find.text('Beta')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _header, matching: find.byType(EditableText)),
        findsNothing,
      );
    },
  );
}
