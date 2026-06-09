/// In-place text editing overlay: a double-click opens it over a text element.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A focused text field positioned over a text element for inline editing
/// (FR-019). Commits on Enter or when focus is lost; cancels on Escape. The
/// host positions it at the element's screen rect.
class InlineTextEditor extends StatefulWidget {
  /// Creates the editor seeded with [initialText].
  const InlineTextEditor({
    required this.initialText,
    required this.onCommit,
    required this.onCancel,
    super.key,
  });

  /// The element's current text.
  final String initialText;

  /// Called with the new text on commit (Enter / blur).
  final ValueChanged<String> onCommit;

  /// Called when editing is abandoned (Escape).
  final VoidCallback onCancel;

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final FocusNode _focusNode = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Intercept Escape before the canvas shortcuts to cancel cleanly.
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ShadInput(
        key: const ValueKey<String>('jet_print.designer.inlineTextEditor'),
        controller: _controller,
        focusNode: _focusNode,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
