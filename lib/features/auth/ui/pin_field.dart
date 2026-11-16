import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

/// Four PIN boxes (dots when filled) driven by one hidden numeric text
/// field, so the phone's number keypad opens on tap.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    this.length = 4,
    this.autofocus = false,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final ValueChanged<String>? onCompleted;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  final _focus = FocusNode();
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    final text = widget.controller.text;
    // Selection changes also notify; only react to real text changes.
    if (text == _lastText) return;
    _lastText = text;
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _Box(
                  filled: i < text.length,
                  active: _focus.hasFocus && i == text.length.clamp(0, widget.length - 1),
                ),
              ],
            ],
          ),
          // Hidden input. Opacity 0 still receives focus and keyboard input.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                obscureText: true,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.filled, required this.active});

  final bool filled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GallaColors.card,
        borderRadius: GallaRadius.card,
        boxShadow: GallaShadows.card,
        border: active ? Border.all(color: GallaColors.ink, width: 2) : null,
      ),
      child: filled
          ? Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: GallaColors.ink,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
