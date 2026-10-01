import '../../models/app_language.dart';
import '../../models/subtitle_segment.dart';

/// Post-process AI caption segments to reduce timing/text errors.
class CaptionPostProcessor {
  CaptionPostProcessor._();

  static const minDuration = Duration(milliseconds: 300);
  static const maxDuration = Duration(seconds: 8);
  static const minGap = Duration(milliseconds: 40);

  static List<SubtitleSegment> clean(
    List<SubtitleSegment> input, {
    Duration? mediaDuration,
  }) {
    final sorted = [...input]..sort((a, b) => a.start.compareTo(b.start));
    final out = <SubtitleSegment>[];

    for (final raw in sorted) {
      var text = raw.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) continue;

      var start = raw.start;
      var end = raw.end;
      if (start.isNegative) start = Duration.zero;
      if (end <= start) {
        end = start + minDuration;
      }
      if (end - start > maxDuration) {
        end = start + maxDuration;
      }
      if (mediaDuration != null && end > mediaDuration) {
        end = mediaDuration;
        if (end - start < minDuration) {
          start = end - minDuration;
          if (start.isNegative) start = Duration.zero;
        }
      }

      if (out.isNotEmpty) {
        final prev = out.last;
        if (start < prev.end + minGap) {
          start = prev.end + minGap;
          if (end - start < minDuration) {
            end = start + minDuration;
          }
          if (mediaDuration != null && end > mediaDuration) {
            // Drop if it no longer fits.
            continue;
          }
        }
      }

      out.add(raw.copyWith(start: start, end: end, text: text));
    }

    return out;
  }
}

/// Build the Gemini prompt from selected languages.
class CaptionPromptBuilder {
  CaptionPromptBuilder._();

  static String fill(
    String template, {
    required AppLanguage source,
    required AppLanguage target,
  }) {
    final translate = source.code != 'auto' && source.code != target.code;
    final mode = translate ? 'TRANSLATE' : 'TRANSCRIBE';
    final sourceLabel = source.code == 'auto'
        ? 'Auto-detect spoken language'
        : source.display;

    return template
        .replaceAll('{{MODE}}', mode)
        .replaceAll('{{SOURCE_LANGUAGE}}', sourceLabel)
        .replaceAll('{{SOURCE_CODE}}', source.code)
        .replaceAll('{{TARGET_LANGUAGE}}', target.display)
        .replaceAll('{{TARGET_CODE}}', target.code);
  }
}
