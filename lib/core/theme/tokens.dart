import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class GallaRadius {
  static const double base = 8;
  static const double thumb = 6;
  static const double round = 999;

  static final card = BorderRadius.circular(base);
  static final thumbnail = BorderRadius.circular(thumb);
}

abstract final class GallaSizes {
  /// Minimum touch target.
  static const double touch = 44;
  static const double primaryButtonHeight = 60;
  static const double navBarHeight = 100;
  static const double centerButton = 68;
  static const double screenPadding = 16;
}

abstract final class GallaShadows {
  /// 0 1px 4px rgba(4,38,15,.16)
  static const card = [
    BoxShadow(
      color: GallaColors.shadow,
      offset: Offset(0, 1),
      blurRadius: 4,
    ),
  ];
}

abstract final class GallaFonts {
  static const body = 'Inter';
  static const display = 'Fredoka';
}

/// Text style helpers. Fredoka Bold for headings, big numbers and button
/// labels; Inter for everything else.
abstract final class GallaText {
  static const display = TextStyle(
    fontFamily: GallaFonts.display,
    fontWeight: FontWeight.w700,
    color: GallaColors.ink,
  );

  static const heading = TextStyle(
    fontFamily: GallaFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    color: GallaColors.ink,
  );

  static const bigNumber = TextStyle(
    fontFamily: GallaFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 40,
    height: 1.1,
    color: GallaColors.ink,
  );

  static const buttonLabel = TextStyle(
    fontFamily: GallaFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 20,
  );

  static const body = TextStyle(
    fontFamily: GallaFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    color: GallaColors.ink,
  );

  static const bodyMedium = TextStyle(
    fontFamily: GallaFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    color: GallaColors.ink,
  );

  static const caption = TextStyle(
    fontFamily: GallaFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: GallaColors.muted,
  );

  static const label = TextStyle(
    fontFamily: GallaFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    color: GallaColors.muted,
  );
}
