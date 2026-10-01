import 'package:flutter_test/flutter_test.dart';

import 'package:ai_subtitle/core/utils/json_cleaner.dart';
import 'package:ai_subtitle/core/utils/timestamp_utils.dart';
import 'package:ai_subtitle/features/export/subtitle_export_service.dart';
import 'package:ai_subtitle/features/subtitle_editor/subtitle_ops.dart';
import 'package:ai_subtitle/models/subtitle_segment.dart';
import 'package:ai_subtitle/models/subtitle_style.dart';
import 'package:ai_subtitle/models/transcription_result.dart';

void main() {
  group('TimestampUtils', () {
    test('formats SRT', () {
      expect(
        TimestampUtils.toSrt(const Duration(milliseconds: 2400)),
        '00:00:02,400',
      );
    });

    test('formats ASS', () {
      expect(
        TimestampUtils.toAss(const Duration(milliseconds: 2400)),
        '0:00:02.40',
      );
    });

    test('parses UI timestamps', () {
      expect(
        TimestampUtils.tryParse('00:02.40'),
        const Duration(milliseconds: 2400),
      );
      expect(
        TimestampUtils.tryParse('00:00:02,400'),
        const Duration(milliseconds: 2400),
      );
    });
  });

  group('JsonCleaner + TranscriptionResult', () {
    test('parses fenced JSON', () {
      const raw = '''
```json
{
  "language": "ckb",
  "segments": [
    {"startMs": 0, "endMs": 2400, "text": "سڵاو، بەخێربێن"},
    {"startMs": 2400, "endMs": 5100, "text": "ئەمڕۆ باسی بابەتێکی گرنگ دەکەین"}
  ]
}
```
''';
      final cleaned = JsonCleaner.clean(raw);
      expect(cleaned.startsWith('{'), isTrue);
      final result = TranscriptionResult.fromRawJson(raw);
      expect(result.language, 'ckb');
      expect(result.segments, hasLength(2));
      expect(result.segments.first.text, 'سڵاو، بەخێربێن');
    });

    test('rejects invalid segments and sorts', () {
      const raw = '''
{
  "language": "ckb",
  "segments": [
    {"startMs": 5000, "endMs": 6000, "text": "دووەم"},
    {"startMs": 10, "endMs": 5, "text": "bad"},
    {"startMs": 0, "endMs": 1000, "text": "یەکەم"},
    {"startMs": 0, "endMs": 1000, "text": ""}
  ]
}
''';
      final result = TranscriptionResult.fromRawJson(raw);
      expect(result.segments, hasLength(2));
      expect(result.segments.first.text, 'یەکەم');
    });
  });

  group('SubtitleSegment', () {
    test('fromJson validation', () {
      expect(
        () => SubtitleSegment.fromJson({
          'startMs': -1,
          'endMs': 10,
          'text': 'x',
        }),
        throwsFormatException,
      );
    });
  });

  group('SRT / ASS generation', () {
    final segments = [
      SubtitleSegment.create(
        start: Duration.zero,
        end: const Duration(milliseconds: 1500),
        text: 'سڵاو',
      ),
      SubtitleSegment.create(
        start: const Duration(milliseconds: 1500),
        end: const Duration(milliseconds: 3000),
        text: 'جیهان',
      ),
    ];
    final export = SubtitleExportService();

    test('SRT', () {
      final srt = export.toSrt(segments);
      expect(srt.contains('1\n'), isTrue);
      expect(srt.contains('00:00:00,000 --> 00:00:01,500'), isTrue);
      expect(srt.contains('سڵاو'), isTrue);
    });

    test('ASS includes style and dialogue', () {
      final ass = export.toAss(
        segments: segments,
        style: const SubtitleStyle(fontFamily: 'NotoSansArabic', fontSize: 52),
        videoWidth: 1080,
        videoHeight: 1920,
      );
      expect(ass.contains('[Script Info]'), isTrue);
      expect(ass.contains('PlayResX: 1080'), isTrue);
      expect(ass.contains('Dialogue:'), isTrue);
      expect(ass.contains('Noto Sans Arabic'), isTrue);
    });
  });

  group('SubtitleOps', () {
    test('split and merge', () {
      final original = [
        SubtitleSegment.create(
          start: Duration.zero,
          end: const Duration(seconds: 4),
          text: 'سڵاو جیهان',
        ),
      ];
      final split = SubtitleOps.split(original, original.first.id);
      expect(split, hasLength(2));
      expect(split.first.end, split.last.start);

      final merged = SubtitleOps.merge(split, split.first.id, split.last.id);
      expect(merged, hasLength(1));
      expect(merged.first.text.contains('سڵاو'), isTrue);
    });

    test('moveSegment shifts timing', () {
      final segments = [
        SubtitleSegment.create(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 3),
          text: 'test',
        ),
      ];
      final moved = SubtitleOps.moveSegment(
        segments,
        segments.first.id,
        const Duration(seconds: 2),
        mediaDuration: const Duration(seconds: 30),
      );
      expect(moved.first.start, const Duration(seconds: 3));
      expect(moved.first.end, const Duration(seconds: 5));
    });

    test('resizeSegment enforces min duration', () {
      final segments = [
        SubtitleSegment.create(
          start: Duration.zero,
          end: const Duration(seconds: 2),
          text: 'test',
        ),
      ];
      final resized = SubtitleOps.resizeSegment(
        segments,
        segments.first.id,
        end: const Duration(milliseconds: 50),
        mediaDuration: const Duration(seconds: 10),
      );
      expect(
        resized.first.duration >= SubtitleOps.minDuration,
        isTrue,
      );
    });
  });
}
