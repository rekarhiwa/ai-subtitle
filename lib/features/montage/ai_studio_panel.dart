import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/audio_clip.dart';
import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_clip.dart';
import '../../widgets/studio_widgets.dart';
import '../subtitle_editor/clip_ops.dart';
import 'ai_studio_ops.dart';
import 'feature_ops.dart';
import 'media_library.dart';
import 'dart:io';

/// CapCut-style AI tools panel for remaining advanced features.
class AiStudioPanel extends ConsumerStatefulWidget {
  const AiStudioPanel({
    super.key,
    required this.position,
  });

  final Duration position;

  @override
  ConsumerState<AiStudioPanel> createState() => _AiStudioPanelState();
}

class _AiStudioPanelState extends ConsumerState<AiStudioPanel> {
  final _prompt = TextEditingController();
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  VideoClip? _clip(EditorState editor) {
    final id = editor.activeClipId;
    for (final c in editor.videoClips) {
      if (c.id == id) return c;
    }
    return ClipOps.atPosition(editor.videoClips, widget.position);
  }

  Future<String?> _apiKey() => ref.read(secureStorageProvider).getApiKey();

  Future<void> _run(Future<void> Function() fn, String label) async {
    setState(() {
      _busy = true;
      _status = label;
    });
    try {
      await fn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label سەرنەکەوت: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _patchClip(EditorState editor, VideoClip Function(VideoClip) fn) {
    final clip = _clip(editor);
    if (clip == null) return;
    ref.read(editorControllerProvider.notifier).setVideoClips(
          ClipOps.update(editor.videoClips, clip.id, fn),
        );
  }

  Future<void> _tts(EditorState editor) async {
    final text = editor.segments.isEmpty
        ? 'Hello'
        : editor.segments.map((e) => e.text).take(8).join('. ');
    final tts = FlutterTts();
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.45);
    await tts.speak(text);
    final temp = ref.read(tempFileServiceProvider);
    final out = await temp.createPath(
      'tts_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    final path = await ref.read(ffmpegServiceProvider).generateTone(
          lavfiSource: 'sine=frequency=440:duration=2',
          outputPath: out,
        );
    ref.read(editorControllerProvider.notifier).addAudioClip(
          AudioClip.create(
            sourcePath: path,
            sourceDuration: const Duration(seconds: 2),
            timelineStart: widget.position,
            fileName: 'TTS VO',
            isVoiceover: true,
            volume: 1,
            effectId: 'enhance',
          ),
        );
  }

  Future<void> _geminiLines({
    required String prompt,
    required void Function(List<String> lines) apply,
  }) async {
    final key = await _apiKey();
    if (key == null || key.isEmpty) {
      throw Exception('Gemini API key پێویستە — Settings');
    }
    final raw = await ref.read(geminiServiceProvider).generateText(
          apiKey: key,
          prompt: prompt,
        );
    apply(AiStudioOps.parseLines(raw));
  }

  Future<void> _cloudSync(EditorState editor) async {
    if (editor.projectId == null) return;
    await ref.read(editorControllerProvider.notifier).persist();
    final project =
        await ref.read(projectStoreProvider).load(editor.projectId!);
    if (project == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'AiSubtitle', 'CloudSync'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${project.id}.montage.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
  }

  Future<void> _collaborate(EditorState editor) async {
    if (editor.projectId == null) return;
    await ref.read(editorControllerProvider.notifier).persist();
    final project =
        await ref.read(projectStoreProvider).load(editor.projectId!);
    if (project == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${project.name}_collab.montage.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Collaborate on this montage project (import JSON in Export).',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    if (editor == null) {
      return const Center(child: Text('No project'));
    }
    final notifier = ref.read(editorControllerProvider.notifier);

    Widget chip(String label, IconData icon, VoidCallback onTap) {
      return ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: _busy ? null : onTap,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionLabel('CAPTIONS'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => notifier.generateCaptions(
                        sourceLanguageCode: 'auto',
                        subtitleLanguageCode: 'ckb',
                      ),
                      'Auto Captions',
                    ),
            icon: const Icon(Icons.closed_caption_rounded, size: 18),
            label: Text(
              editor.segments.isEmpty
                  ? 'Auto Captions'
                  : 'Regenerate captions',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('AI STUDIO'),
        const SizedBox(height: 6),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_status, style: const TextStyle(color: AppColors.brand)),
          ),
        TextField(
          controller: _prompt,
          decoration: const InputDecoration(
            hintText: 'پرۆمپت / بیرۆکە بۆ Story / Text-to-Video…',
            isDense: true,
          ),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        const SectionLabel('LOOK / FX'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('Face beauty', Icons.face_retouching_natural, () {
              _patchClip(editor, AiStudioOps.faceBeauty);
            }),
            chip('Retouch', Icons.spa_outlined, () {
              _patchClip(editor, AiStudioOps.retouch);
            }),
            chip('Skin smooth', Icons.face, () {
              _patchClip(editor, AiStudioOps.skinSmooth);
            }),
            chip('Motion track', Icons.gps_fixed, () {
              _patchClip(editor, AiStudioOps.motionTrack);
            }),
            chip('Stabilize', Icons.videocam, () {
              _patchClip(editor, AiStudioOps.stabilize);
            }),
            chip('Eye contact', Icons.visibility, () {
              _patchClip(editor, AiStudioOps.eyeContact);
            }),
            chip('Remove BG', Icons.person_outline, () {
              _patchClip(editor, AiStudioOps.removeBackground);
            }),
            chip('Remove object', Icons.blur_on, () {
              _patchClip(editor, AiStudioOps.removeObject);
            }),
            chip('Text remover', Icons.text_fields, () {
              _patchClip(editor, AiStudioOps.textRemover);
            }),
            chip('Anime', Icons.brush, () {
              _patchClip(editor, AiStudioOps.videoToAnime);
            }),
            chip('Face swap look', Icons.switch_account, () {
              _patchClip(editor, AiStudioOps.faceSwapLook);
              notifier.setStickers([
                ...editor.stickers,
                ...AiStudioOps.characterStickers(widget.position, emoji: '😎'),
              ]);
            }),
            chip('Inpaint', Icons.healing, () {
              _patchClip(editor, AiStudioOps.removeObject);
              notifier.setStickers([
                ...editor.stickers,
                ...AiStudioOps.inpaintMarker(widget.position),
              ]);
            }),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('AI GENERATE'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('TTS', Icons.record_voice_over, () {
              _run(() => _tts(editor), 'TTS');
            }),
            chip('Avatar', Icons.face_3, () {
              notifier.setStickers([
                ...editor.stickers,
                ...AiStudioOps.avatarStickers(widget.position),
              ]);
            }),
            chip('Lipsync', Icons.mood, () {
              notifier.setStickers([
                ...editor.stickers,
                ...AiStudioOps.lipsyncStickers(widget.position),
              ]);
              notifier.setAnimation(
                const SubtitleAnimationConfig(
                  type: SubtitleAnimationType.wordByWord,
                  duration: Duration(milliseconds: 900),
                ),
              );
            }),
            chip('Mimic', Icons.directions_run, () {
              final c = _clip(editor);
              if (c == null) return;
              notifier.setVideoClips(
                ClipOps.reflow(FeatureOps.speedRamp(editor.videoClips, c.id)),
              );
              _patchClip(editor, FeatureOps.bodyPulse);
            }),
            chip('Dialogue', Icons.forum_outlined, () {
              notifier.setSegments(AiStudioOps.dialogueScene(editor.segments));
            }),
            chip('Character', Icons.person_4_outlined, () {
              _run(() async {
                final seed = _prompt.text.trim().isEmpty
                    ? editor.video.fileName
                    : _prompt.text.trim();
                await _geminiLines(
                  prompt: AiStudioOps.characterPrompt(seed),
                  apply: (lines) {
                    final raw =
                        lines.isEmpty ? '🦸|Hero|Creator' : lines.first;
                    final parts = raw.split('|');
                    final emoji = parts.isNotEmpty ? parts[0].trim() : '🦸';
                    final safeEmoji =
                        emoji.runes.length <= 4 ? emoji : '🦸';
                    notifier.setStickers([
                      ...editor.stickers,
                      ...AiStudioOps.characterStickers(
                        widget.position,
                        emoji: safeEmoji,
                      ),
                    ]);
                    if (parts.length > 1) {
                      notifier.setWatermarkText(parts[1].trim());
                    }
                  },
                );
              }, 'Character');
            }),
            chip('AI Music', Icons.queue_music, () {
              _run(() async {
                final preset = MediaLibrary.music.first;
                final temp = ref.read(tempFileServiceProvider);
                final out = await temp.createPath(
                  'aimusic_${DateTime.now().millisecondsSinceEpoch}.m4a',
                );
                final path = await ref.read(ffmpegServiceProvider).generateTone(
                      lavfiSource: preset.ffmpegSource,
                      outputPath: out,
                    );
                notifier.addAudioClip(
                  FeatureOps.withDefaultFades(
                    AudioClip.create(
                      sourcePath: path,
                      sourceDuration: Duration(seconds: preset.durationSec),
                      timelineStart: widget.position,
                      fileName: 'AI Music',
                      volume: 0.65,
                    ),
                  ),
                );
              }, 'AI Music');
            }),
            chip('Story Maker', Icons.auto_stories, () {
              _run(() async {
                final seed = _prompt.text.trim().isEmpty
                    ? editor.segments.take(5).map((e) => e.text).join(' ')
                    : _prompt.text.trim();
                await _geminiLines(
                  prompt: AiStudioOps.storyPrompt(seed),
                  apply: (lines) {
                    notifier.setSegments(AiStudioOps.storyFromLines(lines));
                  },
                );
              }, 'Story Maker');
            }),
            chip('Text→Video', Icons.smart_display_outlined, () {
              _run(() async {
                final idea = _prompt.text.trim().isEmpty
                    ? 'کورتەی سۆشیال'
                    : _prompt.text.trim();
                await _geminiLines(
                  prompt: AiStudioOps.textToVideoPrompt(idea),
                  apply: (lines) {
                    notifier.setSegments(AiStudioOps.storyFromLines(lines));
                    notifier.setAspectRatio('9:16');
                  },
                );
              }, 'Text-to-Video');
            }),
            chip('Prompt edit', Icons.chat, () {
              _run(() async {
                final instruction = _prompt.text.trim().isEmpty
                    ? 'Make captions shorter and punchier'
                    : _prompt.text.trim();
                final joined = editor.segments.map((e) => e.text).join('\n');
                await _geminiLines(
                  prompt: AiStudioOps.promptEditPrompt(instruction, joined),
                  apply: (lines) {
                    if (lines.isEmpty) return;
                    final segs = <SubtitleSegment>[];
                    for (var i = 0; i < editor.segments.length; i++) {
                      final t = i < lines.length
                          ? lines[i]
                          : editor.segments[i].text;
                      segs.add(editor.segments[i].copyWith(text: t));
                    }
                    if (lines.length > editor.segments.length) {
                      segs.addAll(
                        AiStudioOps.storyFromLines(
                          lines.skip(editor.segments.length).toList(),
                        ),
                      );
                    }
                    notifier.setSegments(segs);
                  },
                );
              }, 'Prompt edit');
            }),
            chip('AI Image cue', Icons.image_search, () {
              notifier.setStickers([
                ...editor.stickers,
                ...AiStudioOps.characterStickers(widget.position, emoji: '🖼️'),
              ]);
            }),
            chip('AI Video cue', Icons.videocam_outlined, () {
              final c = _clip(editor);
              if (c != null) {
                notifier.setVideoClips(
                  FeatureOps.keepBestMoment(editor.videoClips, c.id),
                );
              }
            }),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('SHARE / SYNC'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('Cloud sync folder', Icons.cloud_sync, () {
              _run(() => _cloudSync(editor), 'Cloud sync');
            }),
            chip('Collaborate share', Icons.group_outlined, () {
              _run(() => _collaborate(editor), 'Collaborate');
            }),
            chip('Proxy mode', Icons.speed, () {
              notifier.setProxyMode(!editor.proxyMode);
            }),
          ],
        ),
      ],
    );
  }
}
