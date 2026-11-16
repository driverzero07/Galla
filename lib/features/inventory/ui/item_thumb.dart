import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

/// Item photo (small, cached) or the first letter of the name.
class ItemThumb extends StatelessWidget {
  const ItemThumb({super.key, required this.name, this.photoPath, this.photoUrl, this.size = 44});

  final String name;
  final String? photoPath;

  /// Remote copy (another phone's photo, or after a restore). Used when the
  /// local file is missing; offline it quietly falls back to the letter.
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GallaColors.chip,
        borderRadius: GallaRadius.thumbnail,
      ),
      child: Text(letter,
          style: GallaText.display.copyWith(fontSize: size * 0.45)),
    );
    final path = photoPath;
    final url = photoUrl;
    Widget network() => url == null
        ? fallback
        : ClipRRect(
            borderRadius: GallaRadius.thumbnail,
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, __, ___) => fallback,
            ),
          );
    if (path == null) return network();
    return ClipRRect(
      borderRadius: GallaRadius.thumbnail,
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode small: keeps long lists light on 2 GB phones.
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => network(),
      ),
    );
  }
}
