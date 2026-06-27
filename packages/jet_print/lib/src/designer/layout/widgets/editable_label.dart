/// A label that swaps to an inline text field for renaming a report object.
///
/// Used by the Properties header and the Outline rows so rename behaves
/// identically in both. `editing` is controlled by the parent (which tracks
/// which object is being renamed). Commit trims the input and maps an empty
/// result to `null` (clearing the name → fallback label).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// See library doc. [onCommit] receives the trimmed name, or `null` when empty.
class EditableLabel extends StatefulWidget {
  /// Creates an editable label.
  const EditableLabel({
    super.key,
    required this.display,
    required this.value,
    required this.placeholder,
    required this.onCommit,
    this.editing = false,
    this.onEditingEnd,
    this.textStyle,
  });

  /// The text shown when not editing (the resolved display label).
  final String display;

  /// The raw stored name used to prefill the field (null/blank → empty).
  final String? value;

  /// The hint shown in the empty field (the fallback label).
  final String placeholder;

  /// Called with the trimmed new name, or `null` when the field is left empty.
  final ValueChanged<String?> onCommit;

  /// Whether the inline field is shown (controlled by the parent).
  final bool editing;

  /// Called when the edit ends (after commit, or on Esc cancel).
  final VoidCallback? onEditingEnd;

  /// The text style for the static label.
  final TextStyle? textStyle;

  @override
  State<EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<EditableLabel> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value ?? '');
  final FocusNode _focus = FocusNode();
  bool _committing = false;

  @override
  void didUpdateWidget(EditableLabel old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) {
      _text.text = widget.value ?? '';
      _committing = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focus.requestFocus();
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      });
    }
  }

  void _commit() {
    if (_committing) return;
    _committing = true;
    final String trimmed = _text.text.trim();
    widget.onCommit(trimmed.isEmpty ? null : trimmed);
    widget.onEditingEnd?.call();
  }

  void _cancel() {
    _committing = true; // suppress the focus-loss commit that Esc triggers
    widget.onEditingEnd?.call();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editing) {
      return Text(
        widget.display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.textStyle,
      );
    }
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.placeholder,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
        style: widget.textStyle,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}
