import 'package:flutter/material.dart';

import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_style.dart';

/// Preview subtitle renderer. Reads style + animation independently of Gemini.
class AnimatedSubtitleWidget extends StatefulWidget {
  const AnimatedSubtitleWidget({
    super.key,
    required this.text,
    required this.style,
    required this.animation,
    required this.videoSize,
    this.visible = true,
  });

  final String text;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  final Size videoSize;
  final bool visible;

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

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    final style = widget.style;
    final maxWidth = widget.videoSize.width * style.maxWidth;
    final left = widget.videoSize.width * style.positionX - maxWidth / 2;
    final top = widget.videoSize.height * style.positionY;

    final textWidget = widget.animation.type == SubtitleAnimationType.wordByWord
        ? const SizedBox.shrink()
        : _OutlinedText(
            text: widget.text,
            style: style,
          );

    Widget content = textWidget;
    if (style.backgroundOpacity > 0.01 &&
        style.backgroundColor.a > 0 &&
        widget.animation.type != SubtitleAnimationType.wordByWord) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: style.backgroundColor.withValues(alpha: style.backgroundOpacity),
          borderRadius: BorderRadius.circular(16),
        ),
        child: textWidget,
      );
    }

    return Positioned(
      left: left.clamp(0, widget.videoSize.width),
      top: top.clamp(0, widget.videoSize.height),
      width: maxWidth,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = widget.animation.curve.transform(_controller.value);
          return _applyAnimation(t, child!);
        },
        child: content,
      ),
    );
  }

  Widget _applyAnimation(double t, Widget child) {
    final config = widget.animation;
    switch (config.type) {
      case SubtitleAnimationType.none:
        return child;
      case SubtitleAnimationType.fade:
        final opacity =
            config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);
      case SubtitleAnimationType.pop:
        final scale = config.scaleFrom + (1 - config.scaleFrom) * t;
        final opacity =
            config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      case SubtitleAnimationType.slideUp:
        final dy = config.offsetY * (1 - t);
        final opacity =
            config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      case SubtitleAnimationType.slideLeft:
      case SubtitleAnimationType.slideRight:
        final dx = config.offsetX * (1 - t);
        final opacity =
            config.opacityFrom + (1 - config.opacityFrom) * t;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      case SubtitleAnimationType.wordByWord:
        return _KaraokeText(
          text: widget.text,
          style: widget.style,
          progress: t,
        );
    }
  }
}

class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.text,
    required this.style,
    required this.progress,
  });

  final String text;
  final SubtitleStyle style;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return const SizedBox.shrink();
    final active = (progress * words.length).floor().clamp(0, words.length);
    final baseSize = style.fontSize *
        (MediaQuery.sizeOf(context).shortestSide < 700 ? 0.45 : 0.55);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < words.length; i++)
            Text(
              words[i],
              style: TextStyle(
                fontFamily: style.fontFamily,
                fontSize: baseSize,
                fontWeight: style.fontWeight,
                color: i < active
                    ? style.textColor
                    : style.textColor.withValues(alpha: 0.35),
                shadows: [
                  Shadow(
                    color: i < active
                        ? style.shadowColor
                        : style.shadowColor.withValues(alpha: 0.2),
                    blurRadius: style.shadowBlur,
                    offset: style.shadowOffset,
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
  const _OutlinedText({required this.text, required this.style});

  final String text;
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: style.fontFamily,
      fontSize: style.fontSize *
          (MediaQuery.sizeOf(context).shortestSide < 700 ? 0.45 : 0.55),
      fontWeight: style.fontWeight,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing,
      color: style.textColor,
      shadows: [
        Shadow(
          color: style.shadowColor,
          blurRadius: style.shadowBlur,
          offset: style.shadowOffset,
        ),
      ],
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fake outline via stroked text layers.
          Text(
            text,
            textAlign: style.alignment,
            textDirection: TextDirection.rtl,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = style.outlineWidth
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
