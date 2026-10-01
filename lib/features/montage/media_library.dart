/// Built-in music & SFX presets (generated via FFmpeg lavfi sine/noise).
class MediaPreset {
  const MediaPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.ffmpegSource,
    this.durationSec = 2,
    this.emoji = '🎵',
  });

  final String id;
  final String name;
  final String kind; // music | sfx
  final String ffmpegSource;
  final int durationSec;
  final String emoji;
}

class MediaLibrary {
  MediaLibrary._();

  static const music = <MediaPreset>[
    MediaPreset(
      id: 'pad_a',
      name: 'Soft Pad A',
      kind: 'music',
      ffmpegSource: 'sine=frequency=220:duration=8',
      durationSec: 8,
      emoji: '🎹',
    ),
    MediaPreset(
      id: 'pad_b',
      name: 'Soft Pad B',
      kind: 'music',
      ffmpegSource: 'sine=frequency=330:duration=8',
      durationSec: 8,
      emoji: '🎹',
    ),
    MediaPreset(
      id: 'pulse',
      name: 'Pulse Beat',
      kind: 'music',
      ffmpegSource: 'sine=frequency=110:duration=6',
      durationSec: 6,
      emoji: '🥁',
    ),
    MediaPreset(
      id: 'high_tone',
      name: 'Bright Tone',
      kind: 'music',
      ffmpegSource: 'sine=frequency=523:duration=5',
      durationSec: 5,
      emoji: '✨',
    ),
  ];

  static const sfx = <MediaPreset>[
    MediaPreset(
      id: 'whoosh',
      name: 'Whoosh',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=800:duration=0.35',
      durationSec: 1,
      emoji: '💨',
    ),
    MediaPreset(
      id: 'pop',
      name: 'Pop',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=1200:duration=0.15',
      durationSec: 1,
      emoji: '💥',
    ),
    MediaPreset(
      id: 'click',
      name: 'Click',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=1600:duration=0.08',
      durationSec: 1,
      emoji: '🖱️',
    ),
    MediaPreset(
      id: 'notify',
      name: 'Notify',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=880:duration=0.25',
      durationSec: 1,
      emoji: '🔔',
    ),
    MediaPreset(
      id: 'riser',
      name: 'Riser',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=200:duration=1.2',
      durationSec: 2,
      emoji: '📈',
    ),
    MediaPreset(
      id: 'stock_bass',
      name: 'Stock Bass',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=60:duration=0.5',
      durationSec: 1,
      emoji: '📦',
    ),
    MediaPreset(
      id: 'stock_hit',
      name: 'Stock Hit',
      kind: 'sfx',
      ffmpegSource: 'sine=frequency=90:duration=0.2',
      durationSec: 1,
      emoji: '🎯',
    ),
  ];

  /// Stock media pack (#120).
  static List<MediaPreset> get stock => [
        ...music,
        ...sfx,
      ];

  static List<MediaPreset> get all => stock;
}
