import '../../models/sticker_item.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_clip.dart';
import '../subtitle_editor/subtitle_ops.dart';
import 'feature_ops.dart';

/// Local + Gemini-assisted implementations for remaining CapCut AI features.
class AiStudioOps {
  AiStudioOps._();

  static VideoClip faceBeauty(VideoClip c) => FeatureOps.beautySoft(c);

  static VideoClip motionTrack(VideoClip c) {
    return c.copyWith(
      cameraFx: 'ken_burns',
      panX: 0.08,
      panY: -0.04,
      zoom: 1.12,
    );
  }

  static VideoClip stabilize(VideoClip c) => c.copyWith(stabilize: true);

  static VideoClip retouch(VideoClip c) {
    return c.copyWith(
      beauty: 0.55,
      brightness: 0.06,
      contrast: -0.04,
      saturation: 0.05,
      effectId: 'beauty',
    );
  }

  static VideoClip skinSmooth(VideoClip c) {
    return c.copyWith(beauty: 0.7, effectId: 'blur', contrast: -0.06);
  }

  static VideoClip eyeContact(VideoClip c) {
    return c.copyWith(zoom: 1.14, cropLeft: 0.06, cropRight: 0.06, cropTop: 0.04);
  }

  static VideoClip removeBackground(VideoClip c) {
    return c.copyWith(chromaKey: true, chromaSimilarity: 0.35, maskType: 'soft');
  }

  static VideoClip removeObject(VideoClip c) {
    return c.copyWith(effectId: 'blur', opacity: 0.95, beauty: 0.2);
  }

  static VideoClip textRemover(VideoClip c) {
    return c.copyWith(cropTop: 0.14, brightness: 0.02);
  }

  static VideoClip videoToAnime(VideoClip c) {
    return c.copyWith(
      filterId: 'neon',
      saturation: 0.35,
      contrast: 0.2,
      beauty: 0.25,
      effectId: 'glitch',
    );
  }

  static VideoClip faceSwapLook(VideoClip c) {
    return c.copyWith(beauty: 0.4, zoom: 1.05, effectId: 'body_pulse');
  }

  static List<StickerItem> avatarStickers(Duration at) {
    return [
      StickerItem.create(
        emoji: '🧑‍💻',
        start: at,
        end: at + const Duration(seconds: 4),
        x: 0.5,
        y: 0.28,
        scale: 1.6,
        animated: true,
      ),
    ];
  }

  static List<StickerItem> lipsyncStickers(Duration at) {
    return [
      StickerItem.create(
        emoji: '👄',
        start: at,
        end: at + const Duration(seconds: 2),
        x: 0.5,
        y: 0.55,
        scale: 1.3,
        animated: true,
      ),
    ];
  }

  static List<StickerItem> characterStickers(Duration at, {String emoji = '🦸'}) {
    return [
      StickerItem.create(
        emoji: emoji,
        start: at,
        end: at + const Duration(seconds: 5),
        x: 0.78,
        y: 0.22,
        scale: 1.5,
        animated: true,
      ),
    ];
  }

  static List<StickerItem> inpaintMarker(Duration at) {
    return [
      StickerItem.create(
        emoji: '🩹',
        start: at,
        end: at + const Duration(seconds: 2),
        x: 0.5,
        y: 0.5,
        scale: 1.2,
        opacity: 0.7,
      ),
    ];
  }

  static List<SubtitleSegment> dialogueScene(List<SubtitleSegment> segs) {
    final out = <SubtitleSegment>[];
    for (var i = 0; i < segs.length; i++) {
      final speaker = i.isEven ? 'A' : 'B';
      out.add(segs[i].copyWith(text: '$speaker: ${segs[i].text}'));
    }
    return out;
  }

  static List<SubtitleSegment> storyFromLines(List<String> lines) {
    final out = <SubtitleSegment>[];
    var t = Duration.zero;
    for (final line in lines) {
      final text = line.trim();
      if (text.isEmpty) continue;
      final end = t + Duration(milliseconds: (1800 + text.length * 40).clamp(1200, 5000));
      out.add(SubtitleSegment.create(start: t, end: end, text: text));
      t = end;
    }
    return SubtitleOps.sorted(out);
  }

  static List<String> parseLines(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'[\n•\-]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(40)
        .toList();
  }

  static String storyPrompt(String seed) =>
      'Write a short vertical-video story script in Kurdish Sorani (or mix with English if needed). '
      'Return 8-12 short caption lines only, one per line, no numbering.\nSeed: $seed';

  static String promptEditPrompt(String instruction, String captionsJoined) =>
      'Edit these video captions according to the instruction. '
      'Return only the edited captions, one per line, same count if possible.\n'
      'Instruction: $instruction\nCaptions:\n$captionsJoined';

  static String characterPrompt(String seed) =>
      'Invent one short social-video character name and one emoji. '
      'Reply exactly as: EMOJI|NAME|ONE_LINE_BIO\nSeed: $seed';

  static String textToVideoPrompt(String idea) =>
      'Create a shot list for a 30-second vertical video about: $idea. '
      'Return 6-10 short on-screen caption lines only, one per line.';
}
