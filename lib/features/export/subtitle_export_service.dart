import 'package:flutter/material.dart';

import '../../core/utils/timestamp_utils.dart';
import '../../models/subtitle_segment.dart';
import '../../models/subtitle_style.dart';

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

  /// Generate ASS content from [SubtitleStyle] for burn-in export.
  String toAss({
    required List<SubtitleSegment> segments,
    required SubtitleStyle style,
    required int videoWidth,
    required int videoHeight,
  }) {
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final playResX = videoWidth <= 0 ? 1920 : videoWidth;
    final playResY = videoHeight <= 0 ? 1080 : videoHeight;

    final primary = _assColor(style.textColor);
    final outline = _assColor(style.outlineColor);
    final shadow = _assColor(style.shadowColor);

    final marginV =
        ((1.0 - style.positionY) * playResY).round().clamp(0, playResY);
    final marginL =
        ((1.0 - style.maxWidth) / 2 * playResX).round().clamp(0, playResX);
    final marginR = marginL;
    final bold = style.fontWeight.value >= FontWeight.w700.value ? -1 : 0;
    final fontSize = style.fontSize.round();
    final outlineWidth = style.outlineWidth;
    final shadowDepth = (style.shadowBlur / 3).clamp(0, 8).toDouble();

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
        'Style: Default,${style.fontFamily},$fontSize,$primary,$primary,'
        '$outline,$shadow,$bold,0,0,0,100,100,${style.letterSpacing},0,'
        '1,$outlineWidth,$shadowDepth,2,$marginL,$marginR,$marginV,1',
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
      );

    for (final segment in sorted) {
      final text = segment.text
          .trim()
          .replaceAll('\r\n', r'\N')
          .replaceAll('\n', r'\N');
      buffer.writeln(
        'Dialogue: 0,${TimestampUtils.toAss(segment.start)},'
        '${TimestampUtils.toAss(segment.end)},Default,,0,0,0,,$text',
      );
    }

    return buffer.toString();
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
}
