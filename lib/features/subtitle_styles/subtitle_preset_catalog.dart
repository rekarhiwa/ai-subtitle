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

  static List<SubtitlePreset> get all => const [clean, bold, minimal];

  static SubtitlePreset byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => clean);
  }
}
