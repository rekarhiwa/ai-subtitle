import 'package:uuid/uuid.dart';

/// Music / voiceover / SFX clip on the audio track.
class AudioClip {
  const AudioClip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    required this.timelineStart,
    this.volume = 0.8,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.fileName = '',
    this.speed = 1.0,
    this.effectId = 'none',
    this.muted = false,
    this.solo = false,
    this.isVoiceover = false,
  });

  final String id;
  final String sourcePath;
  final Duration sourceDuration;
  final Duration timelineStart;
  final double volume;
  final int fadeInMs;
  final int fadeOutMs;
  final String fileName;
  final double speed;
  final String effectId;
  final bool muted;
  final bool solo;
  final bool isVoiceover;

  Duration get timelineEnd {
    final ms = (sourceDuration.inMilliseconds / speed.clamp(0.5, 2.0)).round();
    return timelineStart + Duration(milliseconds: ms < 1 ? 1 : ms);
  }

  factory AudioClip.create({
    required String sourcePath,
    required Duration sourceDuration,
    required Duration timelineStart,
    double volume = 0.8,
    String fileName = '',
    double speed = 1.0,
    String effectId = 'none',
    bool muted = false,
    bool solo = false,
    bool isVoiceover = false,
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) {
    return AudioClip(
      id: const Uuid().v4(),
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      timelineStart: timelineStart,
      volume: volume,
      fileName: fileName,
      speed: speed,
      effectId: effectId,
      muted: muted,
      solo: solo,
      isVoiceover: isVoiceover,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
    );
  }

  factory AudioClip.fromJson(Map<String, dynamic> json) {
    return AudioClip(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String,
      sourceDuration: Duration(milliseconds: json['sourceDurationMs'] as int),
      timelineStart: Duration(milliseconds: json['timelineStartMs'] as int),
      volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
      fadeInMs: json['fadeInMs'] as int? ?? 0,
      fadeOutMs: json['fadeOutMs'] as int? ?? 0,
      fileName: (json['fileName'] as String?) ?? '',
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      effectId: json['effectId'] as String? ?? 'none',
      muted: json['muted'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      isVoiceover: json['isVoiceover'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDurationMs': sourceDuration.inMilliseconds,
        'timelineStartMs': timelineStart.inMilliseconds,
        'volume': volume,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'fileName': fileName,
        'speed': speed,
        'effectId': effectId,
        'muted': muted,
        'solo': solo,
        'isVoiceover': isVoiceover,
      };

  AudioClip copyWith({
    Duration? timelineStart,
    double? volume,
    int? fadeInMs,
    int? fadeOutMs,
    String? fileName,
    double? speed,
    String? effectId,
    bool? muted,
    bool? solo,
    bool? isVoiceover,
  }) {
    return AudioClip(
      id: id,
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      timelineStart: timelineStart ?? this.timelineStart,
      volume: volume ?? this.volume,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fileName: fileName ?? this.fileName,
      speed: speed ?? this.speed,
      effectId: effectId ?? this.effectId,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      isVoiceover: isVoiceover ?? this.isVoiceover,
    );
  }
}
