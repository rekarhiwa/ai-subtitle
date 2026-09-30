import '../core/utils/json_cleaner.dart';
import 'subtitle_segment.dart';

class TranscriptionResult {
  const TranscriptionResult({
    required this.language,
    required this.segments,
  });

  final String language;
  final List<SubtitleSegment> segments;

  factory TranscriptionResult.fromRawJson(String raw) {
    final map = JsonCleaner.parseObject(raw);
    final language = (map['language'] ?? 'ckb').toString();
    final list = map['segments'];
    if (list is! List) {
      throw const FormatException('Missing segments array');
    }

    final segments = <SubtitleSegment>[];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        segments.add(
          SubtitleSegment.fromJson(Map<String, dynamic>.from(item)),
        );
      } catch (_) {
        // Skip invalid segment; keep parsing others.
      }
    }

    if (segments.isEmpty) {
      throw const FormatException('No valid subtitle segments returned');
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    return TranscriptionResult(language: language, segments: segments);
  }
}
