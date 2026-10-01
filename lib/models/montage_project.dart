import 'package:flutter/material.dart';

import 'audio_clip.dart';
import 'export_quality.dart';
import 'sticker_item.dart';
import 'subtitle_animation_config.dart';
import 'subtitle_segment.dart';
import 'subtitle_style.dart';
import 'video_clip.dart';
import 'video_metadata.dart';

/// Persisted montage project (video + captions + audio + stickers).
class MontageProject {
  const MontageProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.primaryVideo,
    this.videoClips = const [],
    this.captions = const [],
    this.audioClips = const [],
    this.stickers = const [],
    this.style = const SubtitleStyle(),
    this.animation = SubtitleAnimationConfig.fade,
    this.presetId = 'clean',
    this.exportQuality = ExportQuality.balanced,
    this.muteOriginalAudio = false,
    this.aspectRatio = '9:16',
    this.canvasColor = 0xFF000000,
    this.snapEnabled = true,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VideoMetadata primaryVideo;
  final List<VideoClip> videoClips;
  final List<SubtitleSegment> captions;
  final List<AudioClip> audioClips;
  final List<StickerItem> stickers;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  final String presetId;
  final ExportQuality exportQuality;
  final bool muteOriginalAudio;
  final String aspectRatio;
  final int canvasColor;
  final bool snapEnabled;

  Duration get timelineDuration {
    var maxMs = primaryVideo.duration.inMilliseconds;
    for (final c in videoClips) {
      if (c.timelineEnd.inMilliseconds > maxMs) {
        maxMs = c.timelineEnd.inMilliseconds;
      }
    }
    for (final a in audioClips) {
      if (a.timelineEnd.inMilliseconds > maxMs) {
        maxMs = a.timelineEnd.inMilliseconds;
      }
    }
    for (final s in captions) {
      if (s.end.inMilliseconds > maxMs) maxMs = s.end.inMilliseconds;
    }
    return Duration(milliseconds: maxMs);
  }

  MontageProject copyWith({
    String? name,
    DateTime? updatedAt,
    VideoMetadata? primaryVideo,
    List<VideoClip>? videoClips,
    List<SubtitleSegment>? captions,
    List<AudioClip>? audioClips,
    List<StickerItem>? stickers,
    SubtitleStyle? style,
    SubtitleAnimationConfig? animation,
    String? presetId,
    ExportQuality? exportQuality,
    bool? muteOriginalAudio,
    String? aspectRatio,
    int? canvasColor,
    bool? snapEnabled,
  }) {
    return MontageProject(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      primaryVideo: primaryVideo ?? this.primaryVideo,
      videoClips: videoClips ?? this.videoClips,
      captions: captions ?? this.captions,
      audioClips: audioClips ?? this.audioClips,
      stickers: stickers ?? this.stickers,
      style: style ?? this.style,
      animation: animation ?? this.animation,
      presetId: presetId ?? this.presetId,
      exportQuality: exportQuality ?? this.exportQuality,
      muteOriginalAudio: muteOriginalAudio ?? this.muteOriginalAudio,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      canvasColor: canvasColor ?? this.canvasColor,
      snapEnabled: snapEnabled ?? this.snapEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'primaryVideo': {
          'path': primaryVideo.path,
          'fileName': primaryVideo.fileName,
          'durationMs': primaryVideo.duration.inMilliseconds,
          'width': primaryVideo.width,
          'height': primaryVideo.height,
          'fileSizeBytes': primaryVideo.fileSizeBytes,
          'thumbnailPath': primaryVideo.thumbnailPath,
        },
        'videoClips': videoClips.map((e) => e.toJson()).toList(),
        'captions': captions.map((e) => e.toJson()).toList(),
        'audioClips': audioClips.map((e) => e.toJson()).toList(),
        'stickers': stickers.map((e) => e.toJson()).toList(),
        'style': style.toJson(),
        'animation': animation.type.name,
        'presetId': presetId,
        'exportQuality': exportQuality.name,
        'muteOriginalAudio': muteOriginalAudio,
        'aspectRatio': aspectRatio,
        'canvasColor': canvasColor,
        'snapEnabled': snapEnabled,
      };

  factory MontageProject.fromJson(Map<String, dynamic> json) {
    final v = json['primaryVideo'] as Map<String, dynamic>;
    final animName = json['animation'] as String? ?? 'fade';
    final animType = SubtitleAnimationType.values.firstWhere(
      (e) => e.name == animName,
      orElse: () => SubtitleAnimationType.fade,
    );
    final qualityName = json['exportQuality'] as String? ?? 'balanced';
    final quality = ExportQuality.values.firstWhere(
      (e) => e.name == qualityName,
      orElse: () => ExportQuality.balanced,
    );

    return MontageProject(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      primaryVideo: VideoMetadata(
        path: v['path'] as String,
        fileName: v['fileName'] as String,
        duration: Duration(milliseconds: v['durationMs'] as int),
        width: v['width'] as int,
        height: v['height'] as int,
        fileSizeBytes: v['fileSizeBytes'] as int,
        thumbnailPath: v['thumbnailPath'] as String?,
      ),
      videoClips: [
        for (final e in (json['videoClips'] as List? ?? const []))
          VideoClip.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      captions: [
        for (final e in (json['captions'] as List? ?? const []))
          SubtitleSegment.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      audioClips: [
        for (final e in (json['audioClips'] as List? ?? const []))
          AudioClip.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      stickers: [
        for (final e in (json['stickers'] as List? ?? const []))
          StickerItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      style: _styleFromJson(json['style'] as Map<String, dynamic>?),
      animation: switch (animType) {
        SubtitleAnimationType.none => SubtitleAnimationConfig.none,
        SubtitleAnimationType.fade => SubtitleAnimationConfig.fade,
        SubtitleAnimationType.pop => SubtitleAnimationConfig.pop,
        SubtitleAnimationType.slideUp => SubtitleAnimationConfig.slideUp,
        SubtitleAnimationType.slideLeft => SubtitleAnimationConfig.slideLeft,
        SubtitleAnimationType.slideRight => SubtitleAnimationConfig.slideRight,
        SubtitleAnimationType.wordByWord => SubtitleAnimationConfig.fade,
      },
      presetId: json['presetId'] as String? ?? 'clean',
      exportQuality: quality,
      muteOriginalAudio: json['muteOriginalAudio'] as bool? ?? false,
      aspectRatio: json['aspectRatio'] as String? ?? '9:16',
      canvasColor: json['canvasColor'] as int? ?? 0xFF000000,
      snapEnabled: json['snapEnabled'] as bool? ?? true,
    );
  }

  static SubtitleStyle _styleFromJson(Map<String, dynamic>? json) {
    if (json == null) return const SubtitleStyle();
    return SubtitleStyle(
      fontFamily: json['fontFamily'] as String? ?? 'NotoSansArabic',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 52,
      fontWeight: FontWeight.values.firstWhere(
        (w) => w.value == (json['fontWeight'] as int? ?? 700),
        orElse: () => FontWeight.w700,
      ),
      textColor: Color(json['textColor'] as int? ?? Colors.white.toARGB32()),
      outlineColor:
          Color(json['outlineColor'] as int? ?? const Color(0xCC000000).toARGB32()),
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 2.5,
      shadowColor:
          Color(json['shadowColor'] as int? ?? const Color(0x99000000).toARGB32()),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 6,
      shadowOffset: Offset(
        (json['shadowOffsetX'] as num?)?.toDouble() ?? 0,
        (json['shadowOffsetY'] as num?)?.toDouble() ?? 2,
      ),
      backgroundColor: Color(
        json['backgroundColor'] as int? ?? Colors.transparent.toARGB32(),
      ),
      backgroundOpacity: (json['backgroundOpacity'] as num?)?.toDouble() ?? 0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.5,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.72,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.35,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      maxWidth: (json['maxWidth'] as num?)?.toDouble() ?? 0.86,
    );
  }
}
