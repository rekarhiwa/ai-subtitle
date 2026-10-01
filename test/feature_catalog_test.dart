import 'package:ai_subtitle/features/montage/feature_catalog.dart';
import 'package:ai_subtitle/features/subtitle_editor/clip_ops.dart';
import 'package:ai_subtitle/features/subtitle_editor/subtitle_ops.dart';
import 'package:ai_subtitle/models/video_clip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeatureCatalog', () {
    test('has exactly 136 features including Kurdish captions', () {
      final all = FeatureCatalog.all();
      expect(all.length, FeatureCatalog.total);
      expect(FeatureCatalog.total, 136);
      expect(all.last.number, 136);
      expect(all.last.id, 'kurdish_ai_subtitles');
      expect(all.map((f) => f.number).toSet().length, 136);
    });
  });

  group('ClipOps effects', () {
    test('speed changes timeline duration', () {
      final clip = VideoClip.create(
        sourcePath: 'a.mp4',
        sourceDuration: const Duration(seconds: 10),
        timelineStart: Duration.zero,
        outPoint: const Duration(seconds: 4),
        speed: 2,
      );
      expect(clip.trimmedDuration, const Duration(seconds: 2));
    });

    test('duplicate and reverse', () {
      final a = VideoClip.create(
        sourcePath: 'a.mp4',
        sourceDuration: const Duration(seconds: 5),
        timelineStart: Duration.zero,
      );
      final duped = ClipOps.duplicate([a], a.id);
      expect(duped.length, 2);
      final rev = ClipOps.toggleReverse(duped, duped.first.id);
      expect(rev.first.reversed, isTrue);
    });
  });

  group('SubtitleOps.parseSrt', () {
    test('parses basic SRT', () {
      const srt = '''
1
00:00:01,000 --> 00:00:03,000
سڵاو

2
00:00:04,000 --> 00:00:05,500
چۆنی؟
''';
      final segs = SubtitleOps.parseSrt(srt);
      expect(segs.length, 2);
      expect(segs.first.text, 'سڵاو');
      expect(segs.last.end, const Duration(seconds: 5, milliseconds: 500));
    });
  });
}
