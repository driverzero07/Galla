import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';

/// The "G." mark: ink circle, lime Fredoka G, small white dot bottom-right.
class GallaLogo extends StatelessWidget {
  const GallaLogo({super.key, this.size = 44, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: GallaColors.ink,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              'G',
              style: GallaText.display.copyWith(
                color: GallaColors.lime,
                fontSize: size * 0.58,
                height: 1,
              ),
            ),
          ),
          Positioned(
            right: size * 0.1,
            bottom: size * 0.1,
            child: Container(
              width: size * 0.16,
              height: size * 0.16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return mark;
    return InkResponse(
      onTap: onTap,
      radius: size * 0.8,
      child: mark,
    );
  }
}
