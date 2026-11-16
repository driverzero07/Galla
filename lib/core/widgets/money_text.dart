import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../utils/money.dart';

enum MoneyTone { ink, udhaar, received, onDark, danger }

/// Renders integer paisa as `Rs 1,84,300` in Fredoka Bold.
/// [signed] prefixes `+` / `-` (used in history lists).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.paisa, {
    super.key,
    this.tone = MoneyTone.ink,
    this.size = 16,
    this.signed = false,
    this.symbol = true,
    this.textAlign,
  });

  final int paisa;
  final MoneyTone tone;
  final double size;
  final bool signed;
  final bool symbol;
  final TextAlign? textAlign;

  Color get _color => switch (tone) {
        MoneyTone.ink => GallaColors.ink,
        MoneyTone.udhaar => GallaColors.udhaar,
        MoneyTone.received => GallaColors.received,
        MoneyTone.onDark => GallaColors.lime,
        MoneyTone.danger => GallaColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    var text = formatPaisa(paisa.abs(), symbol: symbol);
    if (signed) {
      text = '${paisa < 0 ? '-' : '+'} $text';
    } else if (paisa < 0) {
      text = '-$text';
    }
    return Text(
      text,
      textAlign: textAlign,
      style: GallaText.display.copyWith(fontSize: size, color: _color),
    );
  }
}
