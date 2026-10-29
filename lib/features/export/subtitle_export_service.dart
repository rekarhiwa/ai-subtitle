import 'package:flutter/material.dart';

import '../../core/utils/timestamp_utils.dart';
import '../../models/sticker_item.dart';
import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_segment.dart';
import '../../models/subtitle_style.dart';
import 'subtitle_layout.dart';

class SubtitleExportService {
  /// Generate SRT content.
  String toSrt(List<SubtitleSegment> segments) {
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final buffer = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      buffer.writeln('${i + 1}');
      buffer.writeln(
        '${TimestampUtils.toSrt(s.start)} --> ${TimestampUtils.toSrt(s.end)}',
      );
      buffer.writeln(s.text.trim());
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Generate ASS for burn-in. Center `\pos` matches Flutter preview anchor.
  String toAss({
    required List<SubtitleSegment> segments,
    required SubtitleStyle style,
    required int videoWidth,
    required int videoHeight,
    List<StickerItem> stickers = const [],
    SubtitleAnimationConfig animation = SubtitleAnimationConfig.none,
  }) {
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final playResX = videoWidth <= 0 ? 1920 : videoWidth;
    final playResY = videoHeight <= 0 ? 1080 : videoHeight;

    final primary = _assColor(style.textColor);
    final outline = _assColor(style.outlineColor);
    final shadow = _assColor(style.shadowColor);

    final bold = style.fontWeight.value >= FontWeight.w700.value ? -1 : 0;
    final fontSize = style.fontSize.round().clamp(8, 400);
    final outlineWidth = style.outlineWidth.clamp(0, 12);
    final shadowDepth = (style.shadowBlur / 3).clamp(0, 8).toDouble();
    final stickerBase = SubtitleLayout.stickerBaseSize(playResY.toDouble())
        .round()
        .clamp(24, 200);

    final posX = SubtitleLayout.assPosX(style, playResX);
    final posY = SubtitleLayout.assPosY(style, playResY);

    final buffer = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('ScriptType: v4.00+')
      ..writeln('WrapStyle: 0')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln('YCbCr Matrix: TV.709')
      ..writeln('PlayResX: $playResX')
      ..writeln('PlayResY: $playResY')
      ..writeln()
      ..writeln('[V4+ Styles]')
      ..writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
        'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
        'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
        'Alignment, MarginL, MarginR, MarginV, Encoding',
      )
      ..writeln(
        'Style: Default,${_assFontName(style.fontFamily)},$fontSize,$primary,$primary,'
        '$outline,$shadow,$bold,0,0,0,100,100,${style.letterSpacing},0,'
        '1,$outlineWidth,$shadowDepth,5,0,0,0,1',
      )
      ..writeln(
        'Style: Sticker,Segoe UI Emoji,$stickerBase,&H00FFFFFF,&H00FFFFFF,'
        '&H00000000,&H80000000,0,0,0,0,100,100,0,0,'
        '1,0,0,5,0,0,0,1',
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
      );

    for (final segment in sorted) {
      final text = _escapeAssText(segment.text.trim());
      final tags = _dialogueTags(
        animation: animation,
        posX: posX,
        posY: posY,
        playResY: playResY,
      );
      buffer.writeln(
        'Dialogue: 0,${TimestampUtils.toAss(segment.start)},'
        '${TimestampUtils.toAss(segment.end)},Default,,0,0,0,,'
        '{$tags}$text',
      );
    }

    for (final sticker in stickers) {
      final px = (sticker.x * playResX).round();
      final py = (sticker.y * playResY).round();
      final scale = (sticker.scale * 100).round().clamp(40, 250);
      buffer.writeln(
        'Dialogue: 1,${TimestampUtils.toAss(sticker.start)},'
        '${TimestampUtils.toAss(sticker.end)},Sticker,,0,0,0,,'
        '{\\an5\\pos($px,$py)\\fscx$scale\\fscy$scale}${sticker.emoji}',
      );
    }

    return buffer.toString();
  }

  String _escapeAssText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('\r\n', r'\N')
        .replaceAll('\n', r'\N');
  }

  String _dialogueTags({
    required SubtitleAnimationConfig animation,
    required int posX,
    required int posY,
    required int playResY,
  }) {
    final ms = animation.duration.inMilliseconds.clamp(80, 2000);
    final scale = playResY / 1080.0;

    switch (animation.type) {
      case SubtitleAnimationType.none:
        return '\\an5\\pos($posX,$posY)';
      case SubtitleAnimationType.fade:
      case SubtitleAnimationType.wordByWord:
        return '\\an5\\pos($posX,$posY)\\fad($ms,$ms)';
      case SubtitleAnimationType.pop:
        final from = (animation.scaleFrom * 100).round().clamp(40, 100);
        return '\\an5\\pos($posX,$posY)\\fad(${ms ~/ 2},${ms ~/ 2})'
            '\\fscx$from\\fscy$from\\t(0,$ms,\\fscx100\\fscy100)';
      case SubtitleAnimationType.slideUp:
        final dy = (animation.offsetY.abs() * scale).round();
        return '\\an5\\move($posX,${posY + dy},$posX,$posY,0,$ms)\\fad(${ms ~/ 2},${ms ~/ 2})';
      case SubtitleAnimationType.slideLeft:
        final dx = (animation.offsetX.abs() * scale).round();
        return '\\an5\\move(${posX + dx},$posY,$posX,$posY,0,$ms)\\fad(${ms ~/ 2},${ms ~/ 2})';
      case SubtitleAnimationType.slideRight:
        final dx = (animation.offsetX.abs() * scale).round();
        return '\\an5\\move(${posX - dx},$posY,$posX,$posY,0,$ms)\\fad(${ms ~/ 2},${ms ~/ 2})';
    }
  }

  /// ASS colors are &HAABBGGRR (alpha inverted).
  String _assColor(Color color) {
    final a = (255 - (color.a * 255).round()).clamp(0, 255);
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return ('&H'
            '${a.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${r.toRadixString(16).padLeft(2, '0')}')
        .toUpperCase();
  }

  String _assFontName(String family) {
    switch (family) {
      case 'NotoSansArabic':
        return 'Noto Sans Arabic';
      case 'sans-serif':
        return 'sans-serif';
      default:
        return family;
    }
  }
}
