import 'package:flutter_test/flutter_test.dart';

import 'package:ai_subtitle/features/subtitle_editor/caption_ai_helpers.dart';
import 'package:ai_subtitle/models/app_language.dart';
import 'package:ai_subtitle/models/subtitle_segment.dart';

void main() {
  group('CaptionPromptBuilder', () {
    test('transcribe when source matches target', () {
      final prompt = CaptionPromptBuilder.fill(
        'MODE={{MODE}} SRC={{SOURCE_CODE}} TGT={{TARGET_CODE}}',
        source: AppLanguage.kurdishSorani,
        target: AppLanguage.kurdishSorani,
      );
      expect(prompt, contains('TRANSCRIBE'));
      expect(prompt, contains('ckb'));
    });

    test('translate when source differs', () {
      final prompt = CaptionPromptBuilder.fill(
        'MODE={{MODE}} SRC={{SOURCE_CODE}} TGT={{TARGET_CODE}}',
        source: AppLanguage.arabic,
        target: AppLanguage.kurdishSorani,
      );
      expect(prompt, contains('TRANSLATE'));
      expect(prompt, contains('ar'));
      expect(prompt, contains('ckb'));
    });
  });

  group('CaptionPostProcessor', () {
    test('removes empty and fixes overlaps', () {
      final cleaned = CaptionPostProcessor.clean([
        SubtitleSegment(
          id: '1',
          start: Duration.zero,
          end: const Duration(milliseconds: 1000),
          text: '  سڵاو  ',
        ),
        SubtitleSegment(
          id: '2',
          start: const Duration(milliseconds: 800),
          end: const Duration(milliseconds: 1500),
          text: 'باشیت',
        ),
        SubtitleSegment(
          id: '3',
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
          text: '   ',
        ),
      ]);
      expect(cleaned.length, 2);
      expect(cleaned.first.text, 'سڵاو');
      expect(cleaned[1].start >= cleaned.first.end, isTrue);
    });
  });
}
