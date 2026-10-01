import 'package:flutter/material.dart';

import '../../models/subtitle_style.dart';

class SubtitlePreset {
  const SubtitlePreset({
    required this.id,
    required this.name,
    required this.style,
  });

  final String id;
  final String name;
  final SubtitleStyle style;
}

/// Presets only mutate [SubtitleStyle] — rendering stays shared.
class SubtitlePresetCatalog {
  SubtitlePresetCatalog._();

  static const clean = SubtitlePreset(
    id: 'clean',
    name: 'Clean',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 52,
      fontWeight: FontWeight.w700,
      textColor: Colors.white,
      outlineColor: Color(0xB3000000),
      outlineWidth: 2.2,
      shadowColor: Color(0x99000000),
      shadowBlur: 6,
      shadowOffset: Offset(0, 2),
      positionY: 0.72,
      maxWidth: 0.86,
      lineHeight: 1.35,
    ),
  );

  static const bold = SubtitlePreset(
    id: 'bold',
    name: 'Bold',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 60,
      fontWeight: FontWeight.w800,
      textColor: Colors.white,
      outlineColor: Color(0xE6000000),
      outlineWidth: 3.4,
      shadowColor: Color(0xCC000000),
      shadowBlur: 8,
      shadowOffset: Offset(0, 3),
      positionY: 0.72,
      maxWidth: 0.88,
      lineHeight: 1.3,
    ),
  );

  static const minimal = SubtitlePreset(
    id: 'minimal',
    name: 'Minimal',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 42,
      fontWeight: FontWeight.w600,
      textColor: Colors.white,
      outlineColor: Color(0x80000000),
      outlineWidth: 1.4,
      shadowColor: Color(0x66000000),
      shadowBlur: 4,
      shadowOffset: Offset(0, 1),
      positionY: 0.74,
      maxWidth: 0.82,
      lineHeight: 1.4,
    ),
  );

  static const neon = SubtitlePreset(
    id: 'neon',
    name: 'Neon',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 54,
      fontWeight: FontWeight.w800,
      textColor: Color(0xFF00E5C0),
      outlineColor: Color(0xFF003D33),
      outlineWidth: 1.2,
      shadowColor: Color(0xCC00E5C0),
      shadowBlur: 18,
      shadowOffset: Offset(0, 0),
      positionY: 0.7,
      maxWidth: 0.88,
      lineHeight: 1.3,
    ),
  );

  static const bubble = SubtitlePreset(
    id: 'bubble',
    name: 'Bubble',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 46,
      fontWeight: FontWeight.w700,
      textColor: Color(0xFF111111),
      outlineColor: Color(0xFFFFFFFF),
      outlineWidth: 0,
      shadowColor: Color(0x33000000),
      shadowBlur: 10,
      shadowOffset: Offset(0, 3),
      backgroundColor: Color(0xFFFFFFFF),
      backgroundOpacity: 0.92,
      positionY: 0.68,
      maxWidth: 0.8,
      lineHeight: 1.35,
    ),
  );

  static const title = SubtitlePreset(
    id: 'title',
    name: 'Title',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 72,
      fontWeight: FontWeight.w900,
      textColor: Colors.white,
      outlineColor: Color(0xE6000000),
      outlineWidth: 3,
      shadowColor: Color(0x99000000),
      shadowBlur: 12,
      shadowOffset: Offset(0, 4),
      positionY: 0.42,
      maxWidth: 0.9,
      lineHeight: 1.2,
    ),
  );

  static const lowerThird = SubtitlePreset(
    id: 'lower_third',
    name: 'Lower Third',
    style: SubtitleStyle(
      fontFamily: 'NotoSansArabic',
      fontSize: 40,
      fontWeight: FontWeight.w700,
      textColor: Colors.white,
      outlineColor: Color(0xCC000000),
      outlineWidth: 1.5,
      shadowColor: Color(0x88000000),
      shadowBlur: 6,
      shadowOffset: Offset(0, 2),
      backgroundColor: Color(0xE600E5C0),
      backgroundOpacity: 0.85,
      positionY: 0.82,
      maxWidth: 0.7,
      lineHeight: 1.25,
    ),
  );

  static List<SubtitlePreset> get all => const [
        clean,
        bold,
        minimal,
        neon,
        bubble,
        title,
        lowerThird,
      ];

  /// Montage-style template packs (#116 / #118).
  static List<SubtitlePreset> get templates => all;

  static SubtitlePreset byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => clean);
  }
}
