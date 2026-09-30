import 'package:flutter/animation.dart';

enum SubtitleAnimationType {
  none,
  fade,
  pop,
  slideUp,
  slideLeft,
  slideRight,
  /// Phase 2: karaoke / TikTok captions.
  wordByWord,
}

class SubtitleAnimationConfig {
  const SubtitleAnimationConfig({
    this.type = SubtitleAnimationType.fade,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
    this.scaleFrom = 0.86,
    this.opacityFrom = 0.0,
    this.offsetX = 0,
    this.offsetY = 18,
  });

  final SubtitleAnimationType type;
  final Duration duration;
  final Curve curve;
  final double scaleFrom;
  final double opacityFrom;
  final double offsetX;
  final double offsetY;

  SubtitleAnimationConfig copyWith({
    SubtitleAnimationType? type,
    Duration? duration,
    Curve? curve,
    double? scaleFrom,
    double? opacityFrom,
    double? offsetX,
    double? offsetY,
  }) {
    return SubtitleAnimationConfig(
      type: type ?? this.type,
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      scaleFrom: scaleFrom ?? this.scaleFrom,
      opacityFrom: opacityFrom ?? this.opacityFrom,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }

  static const none = SubtitleAnimationConfig(type: SubtitleAnimationType.none);

  static const fade = SubtitleAnimationConfig(
    type: SubtitleAnimationType.fade,
    opacityFrom: 0,
    scaleFrom: 1,
    offsetY: 0,
  );

  static const pop = SubtitleAnimationConfig(
    type: SubtitleAnimationType.pop,
    scaleFrom: 0.7,
    opacityFrom: 0,
    curve: Curves.easeOutBack,
  );

  static const slideUp = SubtitleAnimationConfig(
    type: SubtitleAnimationType.slideUp,
    offsetY: 28,
    opacityFrom: 0,
    scaleFrom: 1,
  );

  static const slideLeft = SubtitleAnimationConfig(
    type: SubtitleAnimationType.slideLeft,
    offsetX: 36,
    opacityFrom: 0,
    scaleFrom: 1,
    offsetY: 0,
  );

  static const slideRight = SubtitleAnimationConfig(
    type: SubtitleAnimationType.slideRight,
    offsetX: -36,
    opacityFrom: 0,
    scaleFrom: 1,
    offsetY: 0,
  );

  String get label => switch (type) {
        SubtitleAnimationType.none => 'None',
        SubtitleAnimationType.fade => 'Fade',
        SubtitleAnimationType.pop => 'Pop',
        SubtitleAnimationType.slideUp => 'Slide Up',
        SubtitleAnimationType.slideLeft => 'Slide Left',
        SubtitleAnimationType.slideRight => 'Slide Right',
        SubtitleAnimationType.wordByWord => 'Word by word',
      };
}
