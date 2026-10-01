import 'package:flutter_test/flutter_test.dart';

import 'package:ai_subtitle/features/subtitle_editor/clip_ops.dart';
import 'package:ai_subtitle/models/video_clip.dart';

void main() {
  group('ClipOps', () {
    test('reflow packs clips end to end', () {
      final a = VideoClip.create(
        sourcePath: 'a.mp4',
        sourceDuration: const Duration(seconds: 10),
        timelineStart: Duration.zero,
        outPoint: const Duration(seconds: 4),
      );
      final b = VideoClip.create(
        sourcePath: 'b.mp4',
        sourceDuration: const Duration(seconds: 8),
        timelineStart: const Duration(seconds: 99),
        outPoint: const Duration(seconds: 3),
      );
      final packed = ClipOps.reflow([b, a]);
      expect(packed.first.timelineStart, Duration.zero);
      expect(packed.first.trimmedDuration, const Duration(seconds: 4));
      expect(packed[1].timelineStart, const Duration(seconds: 4));
    });

    test('split creates two clips', () {
      final clip = VideoClip.create(
        sourcePath: 'a.mp4',
        sourceDuration: const Duration(seconds: 10),
        timelineStart: Duration.zero,
      );
      final split = ClipOps.split(
        [clip],
        clip.id,
        const Duration(seconds: 4),
      );
      expect(split.length, 2);
      expect(split.first.outPoint, const Duration(seconds: 4));
      expect(split[1].inPoint, const Duration(seconds: 4));
    });
  });
}
