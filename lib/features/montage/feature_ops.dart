import 'package:flutter/material.dart';

import '../../models/audio_clip.dart';
import '../../models/sticker_item.dart';
import '../../models/subtitle_segment.dart';
import '../../models/subtitle_style.dart';
import '../../models/video_clip.dart';
import '../subtitle_editor/clip_ops.dart';
import '../subtitle_styles/subtitle_preset_catalog.dart';

/// Pure helpers for CapCut-style features (batch 2).
class FeatureOps {
  FeatureOps._();

  static const blendModes = <String, String>{
    'normal': 'Normal',
    'multiply': 'Multiply',
    'screen': 'Screen',
    'overlay': 'Overlay',
    'softlight': 'Soft Light',
  };

  static const videoEffects = <String, String>{
    'none': 'None',
    'shake': 'Shake',
    'blur': 'Blur',
    'glitch': 'Glitch',
    'flash': 'Flash',
    'leak': 'Light leak',
    'body_pulse': 'Body pulse',
    'beauty': 'Beauty soft',
  };

  static const voiceEffects = <String, String>{
    'none': 'None',
    'robot': 'Robot',
    'echo': 'Echo',
    'chipmunk': 'Chipmunk',
    'deep': 'Deep',
    'noise_reduce': 'Noise reduce',
    'enhance': 'Enhance',
  };

  static const maskTypes = <String, String>{
    'none': 'None',
    'circle': 'Circle',
    'rect': 'Rectangle',
    'soft': 'Soft vignette',
  };

  static const cameraFx = <String, String>{
    'none': 'None',
    'zoom_in': '3D Zoom In',
    'zoom_out': '3D Zoom Out',
    'ken_burns': 'Ken Burns',
  };

  static const overlayEmojis = <String>[
    '✨',
    '💫',
    '🌟',
    '⚡',
    '🔥',
    '💥',
    '🌈',
    '☀️',
  ];

  static const brandKits = <String, BrandKit>{
    'teal': BrandKit(
      id: 'teal',
      name: 'Teal Brand',
      primary: Color(0xFF00E5C0),
      accent: Color(0xFFFFFFFF),
      fontFamily: 'NotoSansArabic',
    ),
    'rose': BrandKit(
      id: 'rose',
      name: 'Rose Brand',
      primary: Color(0xFFFF2D55),
      accent: Color(0xFFFFFFFF),
      fontFamily: 'NotoSansArabic',
    ),
    'gold': BrandKit(
      id: 'gold',
      name: 'Gold Brand',
      primary: Color(0xFFFFD60A),
      accent: Color(0xFF111111),
      fontFamily: 'NotoSansArabic',
    ),
  };

  static const trendingTemplateIds = [
    'neon',
    'bubble',
    'bold',
    'lower_third',
    'title',
  ];

  /// One-tap auto enhance (#72).
  static VideoClip autoEnhance(VideoClip c) {
    return c.copyWith(
      brightness: 0.08,
      contrast: 0.12,
      saturation: 0.1,
      vignette: 0.15,
      filterId: c.filterId == 'none' ? 'vivid' : c.filterId,
    );
  }

  static VideoClip beautySoft(VideoClip c) {
    return c.copyWith(beauty: 0.45, brightness: 0.05, contrast: -0.05);
  }

  static VideoClip bodyPulse(VideoClip c) {
    return c.copyWith(effectId: 'body_pulse', zoom: 1.08);
  }

  /// Speed ramp: split into slow→fast segments (#69).
  static List<VideoClip> speedRamp(
    List<VideoClip> clips,
    String id, {
    double from = 0.5,
    double to = 1.5,
  }) {
    final i = clips.indexWhere((c) => c.id == id);
    if (i < 0) return clips;
    final c = clips[i];
    final mid = c.inPoint +
        Duration(milliseconds: c.rawTrimmed.inMilliseconds ~/ 2);
    if (mid <= c.inPoint || mid >= c.outPoint) return clips;
    final left = c.copyWith(outPoint: mid, speed: from);
    final right = c.duplicateAt(c.timelineStart).copyWith(
          inPoint: mid,
          outPoint: c.outPoint,
          speed: to,
        );
    final list = [...clips];
    list[i] = left;
    list.insert(i + 1, right);
    return list;
  }

  static List<AudioClip> normalizeVolumes(
    List<AudioClip> clips, {
    double target = 0.85,
  }) {
    return [for (final a in clips) a.copyWith(volume: target)];
  }

  static List<AudioClip> applyDucking(
    List<AudioClip> clips, {
    double ducked = 0.25,
    double normal = 0.85,
    required bool enabled,
  }) {
    return [
      for (final a in clips)
        a.copyWith(
          volume: a.isVoiceover
              ? normal
              : (enabled ? ducked : (a.volume > 0 ? a.volume : normal)),
        ),
    ];
  }

  static AudioClip withDefaultFades(AudioClip a) {
    return a.copyWith(fadeInMs: 400, fadeOutMs: 600);
  }

  /// Equal-interval AutoCut (#86) / beat sync (#25/#112).
  static List<VideoClip> beatSplit(
    List<VideoClip> clips,
    String id, {
    int bpm = 120,
  }) {
    final i = clips.indexWhere((c) => c.id == id);
    if (i < 0) return clips;
    final c = clips[i];
    final beatMs = (60000 / bpm.clamp(60, 180)).round();
    final raw = c.rawTrimmed.inMilliseconds;
    if (raw < beatMs * 2) return clips;
    final parts = <VideoClip>[];
    var cursor = c.inPoint;
    var first = true;
    while (cursor.inMilliseconds + beatMs < c.outPoint.inMilliseconds) {
      final next = cursor + Duration(milliseconds: beatMs);
      parts.add(
        (first ? c : c.duplicateAt(Duration.zero)).copyWith(
          inPoint: cursor,
          outPoint: next,
        ),
      );
      first = false;
      cursor = next;
    }
    if (cursor < c.outPoint) {
      parts.add(
        c.duplicateAt(Duration.zero).copyWith(
              inPoint: cursor,
              outPoint: c.outPoint,
            ),
      );
    }
    if (parts.length < 2) return clips;
    final list = [...clips];
    list.removeAt(i);
    list.insertAll(i, parts);
    return ClipOps.reflow(list);
  }

  /// Keep middle highlight as "AI Clipper" heuristic (#87).
  static List<VideoClip> keepBestMoment(List<VideoClip> clips, String id) {
    final i = clips.indexWhere((c) => c.id == id);
    if (i < 0) return clips;
    final c = clips[i];
    final third = c.rawTrimmed.inMilliseconds ~/ 3;
    if (third < 400) return clips;
    final start = c.inPoint + Duration(milliseconds: third);
    final end = start + Duration(milliseconds: third);
    return ClipOps.reflow([
      ...clips.where((x) => x.id != id),
      c.copyWith(inPoint: start, outPoint: end),
    ]);
  }

  /// Long → Shorts: 9:16 crop zoom + max 60s (#88).
  static VideoClip longToShorts(VideoClip c) {
    final maxOut = c.inPoint + const Duration(seconds: 60);
    final out = c.outPoint > maxOut ? maxOut : c.outPoint;
    return c.copyWith(
      outPoint: out,
      zoom: 1.15,
      cropLeft: 0.12,
      cropRight: 0.12,
      cameraFx: 'zoom_in',
    );
  }

  static List<StickerItem> autoAlign(
    List<StickerItem> stickers, {
    String mode = 'center',
  }) {
    return [
      for (final s in stickers)
        s.copyWith(
          x: switch (mode) {
            'left' => 0.22,
            'right' => 0.78,
            'top' => s.x,
            _ => 0.5,
          },
          y: switch (mode) {
            'top' => 0.18,
            'bottom' => 0.82,
            _ => 0.35,
          },
        ),
    ];
  }

  static SubtitleStyle applyBrandKit(SubtitleStyle style, BrandKit kit) {
    return style.copyWith(
      textColor: kit.accent,
      outlineColor: kit.primary,
      shadowColor: kit.primary.withValues(alpha: 0.7),
      fontFamily: kit.fontFamily,
      backgroundColor: kit.primary,
      backgroundOpacity: 0.15,
    );
  }

  static SubtitleStyle textTrackingFollow(
    SubtitleStyle style, {
    required double x,
    required double y,
  }) {
    return style.copyWith(positionX: x.clamp(0.1, 0.9), positionY: y.clamp(0.1, 0.9));
  }

  /// Auto lyrics: force karaoke + neon (#47).
  static ({String presetId, SubtitleStyle style}) autoLyricsStyle() {
    final p = SubtitlePresetCatalog.byId('neon');
    return (presetId: p.id, style: p.style);
  }

  static List<SubtitleSegment> smartTemplateFill(
    List<SubtitleSegment> segments,
    String templateId,
  ) {
    // Template fill keeps text; style applied by caller via presetId.
    if (segments.isEmpty) {
      return [
        SubtitleSegment.create(
          start: Duration.zero,
          end: const Duration(seconds: 3),
          text: 'ناونیشان / Title',
        ),
      ];
    }
    return segments;
  }
}

class BrandKit {
  const BrandKit({
    required this.id,
    required this.name,
    required this.primary,
    required this.accent,
    required this.fontFamily,
  });

  final String id;
  final String name;
  final Color primary;
  final Color accent;
  final String fontFamily;
}
