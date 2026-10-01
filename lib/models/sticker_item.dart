import 'package:uuid/uuid.dart';

/// Simple sticker / emoji overlay on the canvas.
class StickerItem {
  const StickerItem({
    required this.id,
    required this.emoji,
    required this.start,
    required this.end,
    this.x = 0.5,
    this.y = 0.35,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.blendMode = 'normal',
    this.animated = false,
    this.rotationDeg = 0,
  });

  final String id;
  final String emoji;
  final Duration start;
  final Duration end;
  final double x;
  final double y;
  final double scale;
  final double opacity;
  final String blendMode;
  final bool animated;
  final double rotationDeg;

  bool contains(Duration position) => position >= start && position < end;

  factory StickerItem.create({
    required String emoji,
    required Duration start,
    required Duration end,
    double x = 0.5,
    double y = 0.35,
    double scale = 1.0,
    double opacity = 1.0,
    String blendMode = 'normal',
    bool animated = false,
    double rotationDeg = 0,
  }) {
    return StickerItem(
      id: const Uuid().v4(),
      emoji: emoji,
      start: start,
      end: end,
      x: x,
      y: y,
      scale: scale,
      opacity: opacity,
      blendMode: blendMode,
      animated: animated,
      rotationDeg: rotationDeg,
    );
  }

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: json['id'] as String,
      emoji: json['emoji'] as String,
      start: Duration(milliseconds: json['startMs'] as int),
      end: Duration(milliseconds: json['endMs'] as int),
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.35,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: json['blendMode'] as String? ?? 'normal',
      animated: json['animated'] as bool? ?? false,
      rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'x': x,
        'y': y,
        'scale': scale,
        'opacity': opacity,
        'blendMode': blendMode,
        'animated': animated,
        'rotationDeg': rotationDeg,
      };

  StickerItem copyWith({
    String? emoji,
    Duration? start,
    Duration? end,
    double? x,
    double? y,
    double? scale,
    double? opacity,
    String? blendMode,
    bool? animated,
    double? rotationDeg,
  }) {
    return StickerItem(
      id: id,
      emoji: emoji ?? this.emoji,
      start: start ?? this.start,
      end: end ?? this.end,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      animated: animated ?? this.animated,
      rotationDeg: rotationDeg ?? this.rotationDeg,
    );
  }
}
