import 'package:flutter_test/flutter_test.dart';

import 'package:ai_subtitle/features/export/subtitle_export_service.dart';
import 'package:ai_subtitle/features/export/subtitle_layout.dart';
import 'package:ai_subtitle/models/subtitle_animation_config.dart';
import 'package:ai_subtitle/models/subtitle_segment.dart';
import 'package:ai_subtitle/models/subtitle_style.dart';

void main() {
  group('SubtitleLayout preview↔ASS parity', () {
    test('ASS→Flutter font factor for Noto Sans Arabic', () {
      expect(
        SubtitleLayout.assToFlutterFontFactor('NotoSansArabic'),
        closeTo(1000 / 2112, 1e-9),
      );
    });

    test('preview font applies resolution + ASS metric conversion', () {
      const style = SubtitleStyle(fontFamily: 'NotoSansArabic', fontSize: 52);
      final preview = SubtitleLayout.previewFontSize(
        style: style,
        previewHeight: 540,
        sourceHeight: 1080,
      );
      // 52 * (540/1080) * (1000/2112) ≈ 12.31
      expect(preview, closeTo(52 * 0.5 * (1000 / 2112), 0.01));
    });

    test('outline scales by resolution only (not font metrics)', () {
      const style = SubtitleStyle(outlineWidth: 4);
      expect(
        SubtitleLayout.previewOutlineWidth(
          style: style,
          previewHeight: 540,
          sourceHeight: 1080,
        ),
        closeTo(2, 0.01),
      );
    });

    test('ASS center pos matches style fractions', () {
      const style = SubtitleStyle(positionX: 0.5, positionY: 0.72);
      expect(SubtitleLayout.assPosX(style, 1080), 540);
      expect(SubtitleLayout.assPosY(style, 1920), (0.72 * 1920).round());
    });

    test('ASS uses an5 + pos and fade tags with raw PlayRes font size', () {
      final export = SubtitleExportService();
      final ass = export.toAss(
        segments: [
          SubtitleSegment.create(
            start: Duration.zero,
            end: const Duration(seconds: 2),
            text: 'سڵاو',
          ),
        ],
        style: const SubtitleStyle(fontSize: 52, positionY: 0.72),
        videoWidth: 1080,
        videoHeight: 1920,
        animation: SubtitleAnimationConfig.fade,
      );
      expect(ass.contains(r'\an5'), isTrue);
      expect(ass.contains(r'\pos('), isTrue);
      expect(ass.contains(r'\fad('), isTrue);
      expect(ass.contains('PlayResY: 1920'), isTrue);
      // Fontsize stays in ASS/PlayRes units (no Flutter EM conversion on export).
      expect(ass.contains(',52,&H'), isTrue);
      // No legacy bottom MarginV positioning for Default style.
      expect(ass.contains(',5,0,0,0,1'), isTrue);
    });

    test('ASS escapes override-breaking characters', () {
      final export = SubtitleExportService();
      final ass = export.toAss(
        segments: [
          SubtitleSegment.create(
            start: Duration.zero,
            end: const Duration(seconds: 1),
            text: r'hello {world} \path',
          ),
        ],
        style: const SubtitleStyle(),
        videoWidth: 1080,
        videoHeight: 1920,
      );
      expect(ass.contains(r'\{world\}'), isTrue);
      expect(ass.contains(r'\\path'), isTrue);
    });
  });
}
