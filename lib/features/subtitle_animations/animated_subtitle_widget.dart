import 'package:flutter/material.dart';

import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_style.dart';
import '../export/subtitle_layout.dart';

/// Preview subtitle renderer — scales from source video pixels so it matches ASS.
class AnimatedSubtitleWidget extends StatefulWidget {
  const AnimatedSubtitleWidget({
    super.key,
    required this.text,
    required this.style,
    required this.animation,
    required this.videoSize,
    required this.sourceSize,
    this.visible = true,
    this.positioned = true,
  });

  final String text;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  /// Displayed preview frame size (widget pixels).
  final Size videoSize;
  /// Native video resolution (PlayRes).
  final Size sourceSize;
  final bool visible;
  /// When false, returns bare content (for [CanvasManipulator] host).
  final bool positioned;

  @override
  State<AnimatedSubtitleWidget> createState() => _AnimatedSubtitleWidgetState();
}

class _AnimatedSubtitleWidgetState extends State<AnimatedSubtitleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animation.duration,
    );
    _lastText = widget.text;
    if (widget.visible && widget.text.isNotEmpty) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedSubtitleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.animation.duration;

    if (widget.text != _lastText) {
      _lastText = widget.text;
      if (widget.visible && widget.text.isNotEmpty) {
        _controller
          ..reset()
          ..forward();
      } else {
        _controller.value = widget.visible ? 1 : 0;
      }
    } else if (widget.visible != oldWidget.visible) {
      if (widget.visible && widget.text.isNotEmpty) {
        _controller.forward(from: 0);
      } else {
        _controller.reverse();
      }
    }

    if (widget.animation.type != oldWidget.animation.type) {
      if (widget.visible && widget.text.isNotEmpty) {
        _controller
          ..reset()
          ..forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Resolution-only scale (outline / shadow / motion). Font metrics are separate.
  double get _resScale => SubtitleLayout.resolutionScale(
        previewHeight: widget.videoSize.height,
        sourceHeight: widget.sourceSize.height,
      );

  double get _previewFontSize => SubtitleLayout.previewFontSize(
        style: widget.style,
        previewHeight: widget.videoSize.height,
        sourceHeight: widget.sourceSize.height,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    final style = widget.style;
    final maxWidth = widget.videoSize.width * style.maxWidth;
    final res = _resScale;

    final textWidget = widget.animation.type == SubtitleAnimationType.wordByWord
        ? const SizedBox.shrink()
        : _OutlinedText(
            text: widget.text,
            style: style,
            fontSize: _previewFontSize,
            resScale: res,
          );

    Widget content = textWidget;
    if (style.backgroundOpacity > 0.01 &&
        style.backgroundColor.a > 0 &&
        widget.animation.type != SubtitleAnimationType.wordByWord) {
      content = Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14 * res.clamp(0.35, 1.5),
          vertical: 8 * res.clamp(0.35, 1.5),
        ),
        decoration: BoxDecoration(
          color: style.backgroundColor.withValues(alpha: style.backgroundOpacity),
          borderRadius: BorderRadius.circular(12 * res.clamp(0.35, 1.5)),
        ),
        child: textWidget,
      );
    }

    // Center-anchored — same as ASS Alignment 5 + \pos.
    // Ignore system text scale so preview matches burn-in pixels.
    final animated = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = widget.animation.curve.transform(_controller.value);
          return _applyAnimation(t, child!);
        },
        child: content,
      ),
    );

    if (!widget.positioned) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: animated,
      );
    }

    return Positioned.fill(
      child: Align(
        alignment: SubtitleLayout.alignmentOf(style),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: animated,
        ),
      ),
    );
  }

  Widget _applyAnimation(double t, Widget child) {
    final config = widget.animation;
    final motionScale = _resScale.clamp(0.35, 2.0);
    switch (config.type) {
      case SubtitleAnimationType.none:
        return child;
      case SubtitleAnimationType.fade:
        final opacity = config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);
      case SubtitleAnimationType.pop:
        final scale = config.scaleFrom + (1 - config.scaleFrom) * t;
        final opacity = config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      case SubtitleAnimationType.slideUp:
        final dy = config.offsetY * motionScale * (1 - t);
        final opacity = config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      case SubtitleAnimationType.slideLeft:
      case SubtitleAnimationType.slideRight:
        final dx = config.offsetX * motionScale * (1 - t);
        final opacity = config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      case SubtitleAnimationType.wordByWord:
        return _KaraokeText(
          text: widget.text,
          style: widget.style,
          progress: t,
          fontSize: _previewFontSize,
          resScale: _resScale,
        );
    }
  }
}

class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.text,
    required this.style,
    required this.progress,
    required this.fontSize,
    required this.resScale,
  });

  final String text;
  final SubtitleStyle style;
  final double progress;
  final double fontSize;
  final double resScale;

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return const SizedBox.shrink();
    final active = (progress * words.length).floor().clamp(0, words.length);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6 * resScale.clamp(0.4, 1.2),
        runSpacing: 4 * resScale.clamp(0.4, 1.2),
        children: [
          for (var i = 0; i < words.length; i++)
            Text(
              words[i],
              style: TextStyle(
                fontFamily: style.fontFamily,
                fontSize: fontSize,
                fontWeight: style.fontWeight,
                color: i < active
                    ? style.textColor
                    : style.textColor.withValues(alpha: 0.35),
                shadows: [
                  Shadow(
                    color: i < active
                        ? style.shadowColor
                        : style.shadowColor.withValues(alpha: 0.2),
                    blurRadius: style.shadowBlur * resScale,
                    offset: Offset(
                      style.shadowOffset.dx * resScale,
                      style.shadowOffset.dy * resScale,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OutlinedText extends StatelessWidget {
  const _OutlinedText({
    required this.text,
    required this.style,
    required this.fontSize,
    required this.resScale,
  });

  final String text;
  final SubtitleStyle style;
  final double fontSize;
  final double resScale;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: style.fontFamily,
      fontSize: fontSize,
      fontWeight: style.fontWeight,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing * resScale,
      color: style.textColor,
      shadows: [
        Shadow(
          color: style.shadowColor,
          blurRadius: style.shadowBlur * resScale,
          offset: Offset(
            style.shadowOffset.dx * resScale,
            style.shadowOffset.dy * resScale,
          ),
        ),
      ],
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            textAlign: style.alignment,
            textDirection: TextDirection.rtl,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = style.outlineWidth * resScale
                ..color = style.outlineColor,
              shadows: const [],
            ),
          ),
          Text(
            text,
            textAlign: style.alignment,
            textDirection: TextDirection.rtl,
            style: base,
          ),
        ],
      ),
    );
  }
}
