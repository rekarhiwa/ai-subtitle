import 'package:flutter/painting.dart';

import '../../models/subtitle_style.dart';

/// Shared math so preview and ASS burn-in use the same size & position.
///
/// [SubtitleStyle.fontSize] is defined in **ASS / PlayResY pixels** (libass
/// real-dimension Fontsize). Flutter uses nominal EM size, so preview must
/// convert via [assToFlutterFontFactor] as well as `previewHeight / sourceHeight`.
class SubtitleLayout {
  SubtitleLayout._();

  /// Noto Sans Arabic OS/2: unitsPerEm=1000, usWinAscent+usWinDescent=2112.
  /// libass Fontsize maps to win metrics; Flutter fontSize maps to EM.
  static const double _notoSansArabicAssToFlutter = 1000 / 2112;

  /// Typical Latin UI fonts (~usWin ≈ 1.2× EM). Used when metrics unknown.
  static const double _defaultAssToFlutter = 1000 / 1200;

  /// Convert ASS Fontsize → Flutter [TextStyle.fontSize] for the same ink height.
  static double assToFlutterFontFactor(String fontFamily) {
    switch (fontFamily) {
      case 'NotoSansArabic':
      case 'Noto Sans Arabic':
        return _notoSansArabicAssToFlutter;
      default:
        return _defaultAssToFlutter;
    }
  }

  static double resolutionScale({
    required double previewHeight,
    required double sourceHeight,
  }) {
    final src = sourceHeight <= 0 ? 1080.0 : sourceHeight;
    return previewHeight / src;
  }

  static double previewFontSize({
    required SubtitleStyle style,
    required double previewHeight,
    required double sourceHeight,
  }) {
    return style.fontSize *
        resolutionScale(
          previewHeight: previewHeight,
          sourceHeight: sourceHeight,
        ) *
        assToFlutterFontFactor(style.fontFamily);
  }

  static double previewOutlineWidth({
    required SubtitleStyle style,
    required double previewHeight,
    required double sourceHeight,
  }) {
    return style.outlineWidth *
        resolutionScale(
          previewHeight: previewHeight,
          sourceHeight: sourceHeight,
        );
  }

  static double previewShadowBlur({
    required SubtitleStyle style,
    required double previewHeight,
    required double sourceHeight,
  }) {
    return style.shadowBlur *
        resolutionScale(
          previewHeight: previewHeight,
          sourceHeight: sourceHeight,
        );
  }

  /// Normalized (0–1) → Flutter [Alignment] for center-anchored captions.
  static Alignment alignmentOf(SubtitleStyle style) {
    return Alignment(
      (style.positionX * 2) - 1,
      (style.positionY * 2) - 1,
    );
  }

  static int assPosX(SubtitleStyle style, int playResX) =>
      (style.positionX * playResX).round().clamp(0, playResX);

  static int assPosY(SubtitleStyle style, int playResY) =>
      (style.positionY * playResY).round().clamp(0, playResY);

  /// Sticker base size (px) at source height — matches preview & ASS.
  static double stickerBaseSize(double sourceHeight) {
    final src = sourceHeight <= 0 ? 1080.0 : sourceHeight;
    return src * 0.055;
  }
}
