import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/audio_clip.dart';
import '../../models/export_quality.dart';
import '../../models/montage_project.dart';
import '../../models/sticker_item.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_clip.dart';
import '../../services/ffmpeg/video_processing_service.dart';
import '../../widgets/studio_widgets.dart';
import '../export/subtitle_layout.dart';
import '../montage/feature_ops.dart';
import '../montage/media_library.dart';
import '../subtitle_animations/animated_subtitle_widget.dart';
import 'caption_timeline.dart';
import 'canvas_manipulator.dart';
import 'clip_ops.dart';
import 'editor_tool_dock.dart';
import 'editor_top_bar.dart';
import 'editor_transport.dart';
import 'subtitle_ops.dart';
import '../../models/subtitle_style.dart';

class SubtitleEditorScreen extends ConsumerStatefulWidget {
  const SubtitleEditorScreen({super.key});

  @override
  ConsumerState<SubtitleEditorScreen> createState() =>
      _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends ConsumerState<SubtitleEditorScreen> {
  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  Duration _position = Duration.zero;
  bool _playing = false;
  EditorTab _tab = EditorTab.edit;
  bool _contextOpen = false;
  bool _previewFullscreen = false;
  String? _loadedMediaPath;
  String? _activeClipId;
  bool _seeking = false;
  int _seekGen = 0;
  bool _disposed = false;
  DateTime _lastUiTick = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeekRequest = DateTime.fromMillisecondsSinceEpoch(0);
  bool _advancingClip = false;
  CanvasManipTarget? _selectedOverlay;
  SubtitleStyle? _styleBeforeGesture;
  StickerItem? _stickerBeforeGesture;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _posSub = _player.stream.position.listen((pos) {
      if (!mounted || _disposed || _seeking || _advancingClip) return;
      final editor = ref.read(editorControllerProvider);
      if (editor == null) return;

      // Prefer the clip under the timeline playhead — never invent one from a gap.
      VideoClip? clip = ClipOps.atPosition(editor.videoClips, _position);
      if (clip == null && _activeClipId != null) {
        final byId =
            editor.videoClips.firstWhereOrNull((c) => c.id == _activeClipId);
        if (byId != null &&
            _position >= byId.timelineStart &&
            _position < byId.timelineEnd) {
          clip = byId;
        }
      }

      if (clip == null) {
        if (_playing) {
          final next = ClipOps.sorted(editor.videoClips)
              .where((c) => c.timelineStart > _position)
              .firstOrNull;
          if (next != null) {
            _advancingClip = true;
            _seekTo(next.timelineStart).whenComplete(() {
              _advancingClip = false;
            });
          } else {
            _player.pause();
          }
        }
        return;
      }

      final intoSource = clip.reversed
          ? clip.outPoint - pos
          : pos - clip.inPoint;
      final intoMs =
          (intoSource.inMilliseconds / clip.speed.clamp(0.25, 4.0)).round();
      var timelinePos = clip.timelineStart + Duration(milliseconds: intoMs);
      if (timelinePos < clip.timelineStart) timelinePos = clip.timelineStart;
      if (timelinePos > clip.timelineEnd) timelinePos = clip.timelineEnd;

      final nearEnd = clip.reversed
          ? pos <= clip.inPoint + const Duration(milliseconds: 60)
          : pos >= clip.outPoint - const Duration(milliseconds: 60);
      if (_playing && nearEnd) {
        final activeClip = clip;
        final next = ClipOps.sorted(editor.videoClips)
            .where((c) =>
                c.timelineStart >=
                    activeClip.timelineEnd - const Duration(milliseconds: 20))
            .where((c) => c.id != activeClip.id)
            .firstOrNull;
        if (next != null) {
          _advancingClip = true;
          _seekTo(next.timelineStart).whenComplete(() {
            _advancingClip = false;
          });
          return;
        }
        _player.pause();
        timelinePos = activeClip.timelineEnd;
      }

      final clamped = timelinePos < Duration.zero
          ? Duration.zero
          : timelinePos > editor.timelineDuration
              ? editor.timelineDuration
              : timelinePos;

      final now = DateTime.now();
      final deltaMs = (clamped - _position).inMilliseconds.abs();
      final shouldPaint =
          now.difference(_lastUiTick) >= const Duration(milliseconds: 50) ||
              deltaMs > 120;
      if (shouldPaint) {
        _lastUiTick = now;
        setState(() => _position = clamped);
      } else {
        _position = clamped;
      }

      // Local highlight only — avoid Riverpod rebuild storms every boundary.
      final active = SubtitleOps.activeAt(editor.segments, clamped);
      if (active?.id != editor.activeSegmentId) {
        ref.read(editorControllerProvider.notifier).setActiveSegment(active?.id);
      }
    });
    _playSub = _player.stream.playing.listen((playing) {
      if (mounted && !_disposed) setState(() => _playing = playing);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || !mounted) return;
      ref.read(editorControllerProvider.notifier).setRouteVisible(true);
      final editor = ref.read(editorControllerProvider);
      if (editor == null) return;
      await _loadEditorMedia(editor, seekTo: Duration.zero);
    });
  }

  Future<void> _loadEditorMedia(
    EditorState editor, {
    Duration? seekTo,
  }) async {
    if (_disposed) return;
    final first = ClipOps.sorted(editor.videoClips).firstOrNull;
    final path = first?.sourcePath ?? editor.video.path;
    final target = seekTo ?? _position;
    try {
      if (_loadedMediaPath != path) {
        await _player.open(Media(path), play: false);
        if (_disposed) return;
        _loadedMediaPath = path;
      }
      await _player.setRate(first?.speed.clamp(0.25, 4.0) ?? 1.0);
      if (_disposed) return;
      _activeClipId = first?.id;
      final clip = ClipOps.atPosition(editor.videoClips, target) ?? first;
      if (clip != null) {
        _activeClipId = clip.id;
        await _player.seek(ClipOps.sourceSeek(clip, target));
      }
      if (mounted && !_disposed) setState(() => _position = target);
    } catch (e) {
      debugPrint('Media reload failed: $e');
    }
  }

  Future<void> _leaveEditor() async {
    final notifier = ref.read(editorControllerProvider.notifier);
    await notifier.persist();
    notifier.setRouteVisible(false);
    notifier.cancelJobs();
    if (mounted) Navigator.of(context).pop();
    // Clear after the route is gone so we don't flash "No project loaded".
    Future.microtask(notifier.clearSessionIfHidden);
  }

  @override
  void dispose() {
    _disposed = true;
    _seekGen++;
    _posSub?.cancel();
    _playSub?.cancel();
    try {
      final notifier = ref.read(editorControllerProvider.notifier);
      notifier.setRouteVisible(false);
      notifier.cancelJobs();
      Future.microtask(notifier.clearSessionIfHidden);
    } catch (_) {}
    _player.dispose();
    super.dispose();
  }

  Future<void> _seekTo(Duration timelinePos) async {
    if (_disposed) return;
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;

    // Debounce scrub storms from timeline drag.
    final now = DateTime.now();
    if (now.difference(_lastSeekRequest) < const Duration(milliseconds: 24) &&
        _seeking) {
      _position = timelinePos;
      return;
    }
    _lastSeekRequest = now;

    final gen = ++_seekGen;
    _seeking = true;
    var target = timelinePos;
    try {
      final clips = ClipOps.sorted(editor.videoClips);
      var clip = ClipOps.atPosition(clips, target);
      if (clip == null && clips.isNotEmpty) {
        // Scrub landed in a gap — snap to nearest clip edge, don't map to last.
        clip = clips.where((c) => c.timelineStart >= target).firstOrNull ??
            clips.last;
        target =
            target < clip.timelineStart ? clip.timelineStart : clip.timelineEnd;
      }
      if (clip == null) {
        if (mounted && gen == _seekGen) setState(() => _position = target);
        return;
      }
      if (_loadedMediaPath != clip.sourcePath) {
        final wasPlaying = _playing;
        await _player.open(Media(clip.sourcePath), play: false);
        if (gen != _seekGen || _disposed) return;
        _loadedMediaPath = clip.sourcePath;
        if (wasPlaying) await _player.play();
      }
      if (gen != _seekGen || _disposed) return;
      _activeClipId = clip.id;
      ref.read(editorControllerProvider.notifier).setActiveClip(clip.id);
      // Preview cannot reverse; keep positive rate (export still needs reverse later).
      await _player.setRate(clip.speed.clamp(0.25, 4.0));
      if (gen != _seekGen || _disposed) return;
      await _player.seek(ClipOps.sourceSeek(clip, target));
      if (mounted && gen == _seekGen) setState(() => _position = target);
    } finally {
      if (gen == _seekGen) _seeking = false;
    }
  }

  Future<void> _runAutoCaptions() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    await _player.pause();
    try {
      await ref.read(editorControllerProvider.notifier).generateCaptions(
            sourceLanguageCode: 'auto',
            subtitleLanguageCode: 'ckb',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ژێرنووس ئامادەیە — دەستکاری لەسەر timeline بکە',
            textDirection: TextDirection.rtl,
          ),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        _tab = EditorTab.text;
        _contextOpen = true;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('missing_api_key')
          ? 'کلیدی Gemini لە Settings زیاد بکە'
          : 'Auto Captions سەرکەوتوو نەبوو';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<String?> _resolveFontsDir() async {
    final fromAssets =
        await ref.read(fontServiceProvider).ensureExportFontsDir();
    if (fromAssets != null) return fromAssets;

    final candidates = [
      p.join(Directory.current.path, 'assets', 'fonts'),
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'fonts',
      ),
    ];
    for (final c in candidates) {
      if (await Directory(c).exists()) return p.normalize(c);
    }
    return null;
  }

  Future<String?> _pickSavePath({
    required String fileName,
    required List<int> bytes,
    required List<String> extensions,
  }) async {
    if (Platform.isAndroid) {
      final path = await ref.read(tempFileServiceProvider).createPath(fileName);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export $fileName',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (uri == null) return null;
    return uri.toFilePath();
  }

  Future<void> _exportSrt() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    final content =
        ref.read(subtitleExportServiceProvider).toSrt(editor.segments);
    final name = '${p.basenameWithoutExtension(editor.video.fileName)}.srt';
    final path = await _pickSavePath(
      fileName: name,
      bytes: utf8.encode(content),
      extensions: const ['srt'],
    );
    if (path == null) return;
    await _afterExport(path, share: Platform.isAndroid);
  }

  Future<void> _exportAss() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    final content = ref.read(subtitleExportServiceProvider).toAss(
          segments: editor.segments,
          style: editor.style,
          videoWidth: editor.video.width,
          videoHeight: editor.video.height,
          stickers: editor.stickers,
          animation: editor.animation,
        );
    final name = '${p.basenameWithoutExtension(editor.video.fileName)}.ass';
    final path = await _pickSavePath(
      fileName: name,
      bytes: utf8.encode(content),
      extensions: const ['ass'],
    );
    if (path == null) return;
    await _afterExport(path, share: Platform.isAndroid);
  }

  Future<void> _exportMp4() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;

    if (editor.segments.isEmpty && editor.stickers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'هیچ ژێرنووس/ستیکەرێک نییە بۆ burn-in. سەرەتا Auto Captions بکە.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    final fileName =
        '${p.basenameWithoutExtension(editor.video.fileName)}_montage.mp4';

    final temp = ref.read(tempFileServiceProvider);
    final export = ref.read(subtitleExportServiceProvider);
    final ffmpeg = ref.read(ffmpegServiceProvider);
    final editorNotifier = ref.read(editorControllerProvider.notifier);
    final job = editorNotifier.beginJob();
    final jobProjectId = editor.projectId;

    late final String outPath;
    if (Platform.isAndroid) {
      // Keep under TempFileService so Settings → Clear Temporary Files works.
      outPath = await temp.createPath(fileName);
    } else {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export MP4',
        fileName: fileName,
        bytes: Uint8List(0),
        type: FileType.custom,
        allowedExtensions: const ['mp4'],
      );
      if (uri == null) return;
      outPath = uri.toFilePath();
    }

    final workDir = await temp.createPath(
      'compose_${DateTime.now().millisecondsSinceEpoch}',
    );
    await Directory(workDir).create(recursive: true);

    try {
      editorNotifier.setExporting(
        isExporting: true,
        progress: 0.02,
        message: 'Composing timeline…',
        clearError: true,
        jobGen: job,
      );

      final clips = ClipOps.sorted(editor.videoClips);
      final composedPath = p.join(workDir, 'composed.mp4');
      String videoForBurn = editor.video.path;

      final primaryPath = clips.isNotEmpty ? clips.first.sourcePath : editor.video.path;
      final needsCompose = clips.length > 1 ||
          (clips.isNotEmpty &&
              (clips.first.sourcePath != editor.video.path ||
                  clips.first.inPoint > Duration.zero ||
                  clips.first.outPoint < clips.first.sourceDuration ||
                  (clips.first.speed - 1.0).abs() > 0.01 ||
                  clips.first.reversed));

      if (clips.isNotEmpty && needsCompose) {
        await ffmpeg.trimAndConcat(
          segments: [
            for (final c in clips)
              TimelineSegmentSpec(
                path: c.sourcePath,
                inPoint: c.inPoint,
                outPoint: c.outPoint,
              ),
          ],
          outputPath: composedPath,
          quality: editor.exportQuality,
          workDir: workDir,
          onProgress: (progress, message) {
            editorNotifier.setExporting(
              isExporting: true,
              progress: progress * 0.35,
              message: message,
              jobGen: job,
            );
          },
        );
        if (!editorNotifier.isJobCurrent(job) ||
            ref.read(editorControllerProvider)?.projectId != jobProjectId) {
          return;
        }
        videoForBurn = composedPath;
      } else if (clips.isNotEmpty) {
        // Single full clip — burn the clip source, not a stale primary path.
        videoForBurn = primaryPath;
      }

      var mixedPath = videoForBurn;
      if (editor.audioClips.isNotEmpty) {
        final music = editor.audioClips.first;
        final mixOut = p.join(workDir, 'mixed.mp4');
        await ffmpeg.mixBackgroundAudio(
          videoPath: videoForBurn,
          audioPath: music.sourcePath,
          outputPath: mixOut,
          audioVolume: music.volume,
          audioDelay: music.timelineStart,
          muteOriginal: editor.muteOriginalAudio,
          onProgress: (progress, message) {
            editorNotifier.setExporting(
              isExporting: true,
              progress: 0.35 + progress * 0.15,
              message: message,
              jobGen: job,
            );
          },
        );
        if (!editorNotifier.isJobCurrent(job) ||
            ref.read(editorControllerProvider)?.projectId != jobProjectId) {
          return;
        }
        mixedPath = mixOut;
      }

      // Keep ASS outside workDir so burn copy stays valid if workDir is cleaned.
      final assPath = await temp.createPath(
        'burn_${DateTime.now().millisecondsSinceEpoch}.ass',
      );
      final assBody = export.toAss(
        segments: editor.segments,
        style: editor.style,
        videoWidth: editor.video.width,
        videoHeight: editor.video.height,
        stickers: editor.stickers,
        animation: editor.animation,
      );
      await File(assPath).writeAsString(assBody, flush: true);
      if (!await File(assPath).exists() || (await File(assPath).length()) < 50) {
        throw Exception('ASS subtitle file was not written correctly');
      }

      editorNotifier.setExporting(
        isExporting: true,
        progress: 0.55,
        message: 'Burning captions…',
        jobGen: job,
      );

      final fontsDir = await _resolveFontsDir();
      if (fontsDir == null) {
        _logMissingFonts();
      }

      await ffmpeg.burnSubtitles(
        videoPath: mixedPath,
        assPath: assPath,
        outputPath: outPath,
        quality: editor.exportQuality,
        fontsDir: fontsDir,
        onProgress: (progress, message) {
          editorNotifier.setExporting(
            isExporting: true,
            progress: 0.55 + progress * 0.45,
            message: message,
            jobGen: job,
          );
        },
      );

      if (!editorNotifier.isJobCurrent(job) ||
          ref.read(editorControllerProvider)?.projectId != jobProjectId) {
        await temp.delete(assPath);
        return;
      }

      if (!await File(outPath).exists()) {
        throw Exception('Export finished but output MP4 was not created');
      }

      editorNotifier.setExporting(
        isExporting: false,
        progress: 1,
        message: 'Export complete',
        lastExportPath: outPath,
        jobGen: job,
      );
      await temp.delete(assPath);
      await _afterExport(outPath, share: Platform.isAndroid, isVideo: true);
    } catch (e) {
      editorNotifier.setExporting(
        isExporting: false,
        errorMessage: e.toString(),
        jobGen: job,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      try {
        await Directory(workDir).delete(recursive: true);
      } catch (_) {}
    }
  }

  void _logMissingFonts() {
    // ignore: avoid_print
    debugPrint(
      'WARN: Export fonts dir missing — captions may be invisible in MP4',
    );
  }

  Future<void> _addVideoClip() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    final ffmpeg = ref.read(ffmpegServiceProvider);
    final meta = await ffmpeg.getVideoMetadata(path);
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    final start = editor.timelineDuration;
    ref.read(editorControllerProvider.notifier).addVideoClip(
          VideoClip.create(
            sourcePath: path,
            sourceDuration: meta.duration,
            timelineStart: start,
            thumbnailPath: meta.thumbnailPath,
            fileName: meta.fileName,
          ),
        );
  }

  Future<void> _addAudioClip() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    // Approximate duration via ffprobe metadata when possible.
    Duration dur = const Duration(seconds: 30);
    try {
      final meta = await ref.read(ffmpegServiceProvider).getVideoMetadata(path);
      dur = meta.duration;
    } catch (_) {}
    ref.read(editorControllerProvider.notifier).addAudioClip(
          AudioClip.create(
            sourcePath: path,
            sourceDuration: dur,
            timelineStart: _position,
            fileName: p.basename(path),
          ),
        );
    setState(() {
      _tab = EditorTab.audio;
      _contextOpen = true;
    });
  }

  Future<void> _showAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text(
                    'Video',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addVideoClip();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: const Text(
                    'Audio',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addAudioClip();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.closed_caption_outlined),
                  title: const Text(
                    'Auto Captions',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _tab = EditorTab.text;
                      _contextOpen = true;
                    });
                    _runAutoCaptions();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _importSrt() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'txt'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    final text = await File(path).readAsString();
    final parsed = SubtitleOps.parseSrt(text);
    if (parsed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هیچ ژێرنووسێک لە فایلەکە نەدۆزرایەوە')),
        );
      }
      return;
    }
    ref.read(editorControllerProvider.notifier).setSegments(parsed);
    setState(() => _tab = EditorTab.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parsed.length} ژێرنووس هاوردە کرا')),
      );
    }
  }

  Future<void> _extractAudio() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    final temp = ref.read(tempFileServiceProvider);
    final out = await temp.createPath(
      'extract_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    try {
      final path = await ref.read(ffmpegServiceProvider).extractAudio(
            videoPath: editor.video.path,
            outputPath: out,
          );
      ref.read(editorControllerProvider.notifier).addAudioClip(
            AudioClip.create(
              sourcePath: path,
              sourceDuration: editor.video.duration,
              timelineStart: Duration.zero,
              fileName: p.basename(path),
            ),
          );
      setState(() => _tab = EditorTab.audio);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دەنگ لە ڤیدیۆ دەرهێنرا')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('دەرهێنانی دەنگ سەرنەکەوت: $e')),
        );
      }
    }
  }

  Future<void> _backupProject() async {
    await ref.read(editorControllerProvider.notifier).persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پڕۆژە پاشەکەوت کرا')),
      );
    }
  }

  Future<void> _addMediaPreset(MediaPreset preset) async {
    final temp = ref.read(tempFileServiceProvider);
    final out = await temp.createPath(
      '${preset.id}_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    try {
      final path = await ref.read(ffmpegServiceProvider).generateTone(
            lavfiSource: preset.ffmpegSource,
            outputPath: out,
          );
      ref.read(editorControllerProvider.notifier).addAudioClip(
            FeatureOps.withDefaultFades(
              AudioClip.create(
                sourcePath: path,
                sourceDuration: Duration(seconds: preset.durationSec),
                timelineStart: _position,
                fileName: '${preset.emoji} ${preset.name}',
                volume: preset.kind == 'sfx' ? 1.0 : 0.7,
              ),
            ),
          );
      setState(() => _tab = EditorTab.audio);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${preset.name} زیادکرا')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('دروستکردنی دەنگ سەرنەکەوت: $e')),
        );
      }
    }
  }

  Future<void> _exportGif() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    final fileName =
        '${p.basenameWithoutExtension(editor.video.fileName)}_clip.gif';
    final notifier = ref.read(editorControllerProvider.notifier);
    final job = notifier.beginJob();
    late final String outPath;
    if (Platform.isAndroid) {
      outPath = await ref.read(tempFileServiceProvider).createPath(fileName);
    } else {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export GIF',
        fileName: fileName,
        bytes: Uint8List(0),
        type: FileType.custom,
        allowedExtensions: const ['gif'],
      );
      if (uri == null) return;
      outPath = uri.toFilePath();
    }
    try {
      notifier.setExporting(
        isExporting: true,
        progress: 0.05,
        message: 'Exporting GIF…',
        clearError: true,
        jobGen: job,
      );
      final path = await ref.read(ffmpegServiceProvider).exportGif(
            videoPath: editor.video.path,
            outputPath: outPath,
            start: _position,
            duration: const Duration(seconds: 3),
          );
      if (!notifier.isJobCurrent(job)) return;
      notifier.setExporting(
        isExporting: false,
        progress: 1,
        lastExportPath: path,
        jobGen: job,
      );
      await _afterExport(path, share: Platform.isAndroid);
    } catch (e) {
      notifier.setExporting(
        isExporting: false,
        errorMessage: e.toString(),
        jobGen: job,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GIF سەرنەکەوت: $e')),
        );
      }
    }
  }

  Future<void> _batchExport() async {
    await _exportSrt();
    await _exportAss();
    await _exportMp4();
  }

  Future<void> _exportProjectJson() async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null || editor.projectId == null) return;
    final project =
        await ref.read(projectStoreProvider).load(editor.projectId!);
    if (project == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(project.toJson());
    final name = '${project.name}.montage.json';
    final path = await _pickSavePath(
      fileName: name,
      bytes: utf8.encode(json),
      extensions: const ['json'],
    );
    if (path == null) return;
    await _afterExport(path, share: Platform.isAndroid);
  }

  Future<void> _importProjectJson() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    try {
      final raw = jsonDecode(await File(path).readAsString());
      if (raw is! Map<String, dynamic>) throw const FormatException('bad json');
      final project = MontageProject.fromJson(raw);
      await ref.read(projectStoreProvider).save(project);
      await ref.read(editorControllerProvider.notifier).openProject(project);
      ref.invalidate(recentProjectsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پڕۆژە هاوردە کرا (cross-device)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import سەرنەکەوت: $e')),
        );
      }
    }
  }

  Future<void> _afterExport(
    String path, {
    bool share = false,
    bool isVideo = false,
  }) async {
    if (!mounted) return;

    // Android exports land in app temp storage — copy into the system gallery
    // so the finished video shows up in Photos / Gallery apps.
    if (Platform.isAndroid && isVideo) {
      final saved = await _saveExportToGallery(path);
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ڤیدیۆکە پاشەکەوتکرا بۆ گەلەری'),
            action: SnackBarAction(
              label: 'کردنەوە',
              onPressed: () {
                unawaited(Gal.open());
              },
            ),
          ),
        );
        // Gallery has a copy — drop the temp export when tracked.
        unawaited(ref.read(tempFileServiceProvider).delete(path));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نەتوانرا بۆ گەلەری پاشەکەوت بکرێت — Share بکە',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      return;
    }

    if (share) {
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Export ready'),
        content: Text(path),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isVideo ? 'Open folder' : 'Open'),
          ),
        ],
      ),
    );
    if (open == true) {
      await OpenFilex.open(isVideo ? p.dirname(path) : path);
    }
  }

  Future<bool> _saveExportToGallery(String path) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) return false;
      }
      await Gal.putVideo(path, album: 'Montage');
      return true;
    } on GalException catch (e) {
      debugPrint('Gallery save failed: ${e.type}');
      return false;
    } catch (e) {
      debugPrint('Gallery save failed: $e');
      return false;
    }
  }

  void _selectTab(EditorTab tab) {
    // Export is top-bar only; motion lives inside Style.
    if (tab == EditorTab.export) {
      final editor = ref.read(editorControllerProvider);
      if (editor != null) unawaited(_showExportSheet(editor));
      return;
    }
    final resolved = tab == EditorTab.animation ? EditorTab.style : tab;
    setState(() {
      // CapCut: every dock tab opens its own contextual section + « back.
      if (_contextOpen && _tab == resolved) {
        _contextOpen = false;
        return;
      }
      _tab = resolved;
      _contextOpen = true;
    });
  }

  void _closeContext() {
    setState(() {
      _contextOpen = false;
    });
  }

  Widget _contextBar(EditorState editor) {
    return CapCutTabContextBar(
      tab: _tab,
      editor: editor,
      position: _position,
      onBack: _closeContext,
      onSeek: _seekTo,
      onOpenTab: _selectTab,
      onAutoCaptions: _runAutoCaptions,
      onImportSrt: _importSrt,
      onImportMedia: _addVideoClip,
      onExtractAudio: _extractAudio,
      onBackup: _backupProject,
      onOpenExport: () => _showExportSheet(editor),
      onAddPreset: _addMediaPreset,
    );
  }

  Future<void> _showExportSheet(EditorState editor) async {
    final notifier = ref.read(editorControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Consumer(
              builder: (context, ref, _) {
                final live = ref.watch(editorControllerProvider);
                if (live == null) return const SizedBox.shrink();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Export',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'MP4 quality',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in ExportQuality.values)
                          QualityChip(
                            label: q.label,
                            selected: live.exportQuality == q,
                            onTap: () => notifier.setExportQuality(q),
                          ),
                      ],
                    ),
                    if (live.isExporting) ...[
                      const SizedBox(height: 14),
                      Text(
                        live.exportMessage.isEmpty
                            ? 'Rendering…'
                            : live.exportMessage,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: live.exportProgress.clamp(0.0, 1.0),
                          minHeight: 3,
                          color: AppColors.playhead,
                          backgroundColor: AppColors.surfaceSoft,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    StudioButton(
                      label: live.isExporting ? 'Rendering…' : 'Export MP4',
                      icon: Icons.movie_creation_outlined,
                      busy: live.isExporting,
                      onPressed: live.isExporting
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _exportMp4();
                            },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StudioButton(
                            label: 'SRT',
                            icon: Icons.subtitles_outlined,
                            filled: false,
                            onPressed: () {
                              Navigator.pop(ctx);
                              _exportSrt();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StudioButton(
                            label: 'ASS',
                            icon: Icons.style_outlined,
                            filled: false,
                            onPressed: () {
                              Navigator.pop(ctx);
                              _exportAss();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    if (editor == null) {
      return const Scaffold(body: Center(child: Text('No project loaded')));
    }
    final active = SubtitleOps.activeAt(editor.segments, _position);
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final notifier = ref.read(editorControllerProvider.notifier);

    final timeline = CaptionTimeline(
      segments: editor.segments,
      videoClips: editor.videoClips,
      audioClips: editor.audioClips,
      position: _position,
      duration: editor.timelineDuration,
      activeId: active?.id ?? editor.activeSegmentId,
      activeClipId: editor.activeClipId,
      thumbnailPath: editor.video.thumbnailPath,
      onSeek: _seekTo,
      onSelect: (s) async {
        notifier.setActiveSegment(s.id);
        // CapCut: selecting a caption opens Text → Edit captions tools.
        setState(() {
          _contextOpen = true;
          _tab = EditorTab.text;
        });
        await _seekTo(s.start);
      },
      onSelectClip: (c) async {
        notifier.setActiveClip(c.id);
        setState(() {
          _contextOpen = true;
          _tab = EditorTab.edit;
        });
        await _seekTo(c.timelineStart);
      },
      onSegmentsChanged: notifier.setSegments,
      onClipsChanged: notifier.setVideoClips,
      onAddMedia: _showAddSheet,
      height: wide ? 180 : 168,
    );

    Widget transportBar() => EditorTransport(
          position: _position,
          duration: editor.timelineDuration,
          playing: _playing,
          canUndo: editor.canUndo,
          canRedo: editor.canRedo,
          fullscreen: _previewFullscreen,
          onPlayPause: () =>
              _playing ? _player.pause() : _player.play(),
          onSeek: _seekTo,
          onUndo: () => notifier.undo(),
          onRedo: () => notifier.redo(),
          onKeyframe: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Keyframes coming soon'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          onFullscreen: () =>
              setState(() => _previewFullscreen = !_previewFullscreen),
        );

    final toolPanel = EditorToolPanel(
      tab: _tab,
      editor: editor,
      position: _position,
      onSeek: _seekTo,
      onExportSrt: _exportSrt,
      onExportAss: _exportAss,
      onExportMp4: _exportMp4,
      asSidePanel: wide,
      onOpenTab: _selectTab,
      onImportMedia: _addVideoClip,
      onImportSrt: _importSrt,
      onExtractAudio: _extractAudio,
      onBackup: _backupProject,
      onAddPreset: _addMediaPreset,
      onExportGif: _exportGif,
      onBatchExport: _batchExport,
      onExportProjectJson: _exportProjectJson,
      onImportProjectJson: _importProjectJson,
      onAutoCaptions: _runAutoCaptions,
      onOpenExport: () => _showExportSheet(editor),
    );

    // Reload player when project / primary media changes (e.g. Import JSON).
    ref.listen<EditorState?>(editorControllerProvider, (prev, next) {
      if (next == null || _disposed) return;
      final prevPath = prev == null
          ? null
          : (ClipOps.sorted(prev.videoClips).firstOrNull?.sourcePath ??
              prev.video.path);
      final nextPath =
          ClipOps.sorted(next.videoClips).firstOrNull?.sourcePath ??
              next.video.path;
      final projectChanged = prev?.projectId != next.projectId;
      final mediaChanged = prevPath != nextPath;
      if (projectChanged || mediaChanged) {
        unawaited(
          _loadEditorMedia(
            next,
            seekTo: projectChanged ? Duration.zero : _position,
          ),
        );
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveEditor();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EditorTopBar(
              title: editor.video.fileName,
              exporting: editor.isExporting,
              progress: editor.exportProgress,
              canUndo: editor.canUndo,
              canRedo: editor.canRedo,
              onUndo: () => notifier.undo(),
              onRedo: () => notifier.redo(),
              onAddMedia: _showAddSheet,
              onBack: _leaveEditor,
              onExport: () => _showExportSheet(editor),
            ),
            if (editor.isExporting)
              LinearProgressIndicator(
                value: editor.exportProgress,
                minHeight: 2,
                color: AppColors.playhead,
                backgroundColor: AppColors.surface,
              ),
            Expanded(
              child: Stack(
                children: [
                  wide
                      ? Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _preview(editor, active),
                                  ),
                                  transportBar(),
                                  if (!_previewFullscreen) timeline,
                                ],
                              ),
                            ),
                            if (!_previewFullscreen)
                              Container(
                                width: 360,
                                color: AppColors.surface,
                                child: _contextOpen
                                    ? _contextBar(editor)
                                    : toolPanel,
                              ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _preview(editor, active),
                            ),
                            transportBar(),
                            if (!_previewFullscreen) ...[
                              timeline,
                              if (_contextOpen)
                                _contextBar(editor)
                              else
                                EditorBottomDock(
                                  tab: _tab,
                                  onTab: _selectTab,
                                ),
                            ],
                          ],
                        ),
                  if (editor.isExporting)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.72),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: editor.exportProgress > 0.02
                                      ? editor.exportProgress
                                      : null,
                                  strokeWidth: 2.5,
                                  color: AppColors.playhead,
                                  backgroundColor: AppColors.surfaceSoft,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                editor.exportMessage.isNotEmpty
                                    ? editor.exportMessage
                                    : 'چاوەڕێ بە…',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${((editor.exportProgress.clamp(0, 1)) * 100).round()}%',
                                style: const TextStyle(
                                  color: AppColors.playhead,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _preview(EditorState editor, SubtitleSegment? active) {
    StickerItem? sticker;
    for (final s in editor.stickers) {
      if (s.contains(_position)) {
        sticker = s;
        break;
      }
    }
    final clip = editor.videoClips.firstWhereOrNull(
          (c) => c.id == editor.activeClipId,
        ) ??
        ClipOps.atPosition(editor.videoClips, _position);

    double aspect = editor.video.aspectRatio;
    switch (editor.aspectRatio) {
      case '9:16':
        aspect = 9 / 16;
      case '16:9':
        aspect = 16 / 9;
      case '1:1':
        aspect = 1;
      case '4:5':
        aspect = 4 / 5;
      case '21:9':
        aspect = 21 / 9;
      default:
        break;
    }

    ColorFilter? colorFilter;
    if (clip != null &&
        (clip.brightness != 0 ||
            clip.contrast != 0 ||
            clip.saturation != 0 ||
            clip.filterId != 'none')) {
      final b = 1 + clip.brightness;
      final c = 1 + clip.contrast;
      var s = 1 + clip.saturation;
      if (clip.filterId == 'bw') s = 0;
      if (clip.filterId == 'vivid') s = s * 1.25;
      if (clip.filterId == 'warm') {
        colorFilter = ColorFilter.matrix(_warmMatrix(b, c, s));
      } else if (clip.filterId == 'cool') {
        colorFilter = ColorFilter.matrix(_coolMatrix(b, c, s));
      } else {
        colorFilter = ColorFilter.matrix(_bcsMatrix(b, c, s));
      }
    }

    return Container(
      color: Color(editor.canvasColor),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var width = constraints.maxWidth;
          var height = width / aspect;
          if (height > constraints.maxHeight) {
            height = constraints.maxHeight;
            width = height * aspect;
          }
          final size = Size(width, height);
          Widget video = Video(controller: _videoController);
          if (clip != null) {
            video = Opacity(
              opacity: clip.opacity.clamp(0.05, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(
                    clip.panX * width,
                    clip.panY * height,
                    0,
                    1,
                  )
                  ..rotateZ(clip.rotationDeg * 3.1415926535 / 180)
                  ..scaleByDouble(
                    (clip.flipH ? -1.0 : 1.0) * clip.zoom.clamp(1.0, 3.0),
                    (clip.flipV ? -1.0 : 1.0) * clip.zoom.clamp(1.0, 3.0),
                    1.0,
                    1.0,
                  ),
                child: video,
              ),
            );
            if (clip.effectId == 'flash' || clip.effectId == 'leak') {
              video = Stack(
                fit: StackFit.expand,
                children: [
                  video,
                  IgnorePointer(
                    child: ColoredBox(
                      color: (clip.effectId == 'flash'
                              ? Colors.white
                              : const Color(0xFFFF8A65))
                          .withValues(alpha: 0.18),
                    ),
                  ),
                ],
              );
            }
          }
          if (colorFilter != null) {
            video = ColorFiltered(colorFilter: colorFilter, child: video);
          }
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    video,
                    if (clip != null && clip.vignette > 0)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(
                                  alpha: clip.vignette * 0.85,
                                ),
                              ],
                              stops: const [0.45, 1],
                            ),
                          ),
                        ),
                      ),
                    // Deselect behind overlays so empty taps clear selection.
                    if (_selectedOverlay != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => setState(() => _selectedOverlay = null),
                        ),
                      ),
                    if (active != null)
                      CanvasManipulator(
                        canvasSize: size,
                        nx: editor.style.positionX,
                        ny: editor.style.positionY,
                        scale: editor.style.fontSize,
                        minScale: 24,
                        maxScale: 120,
                        maxWidthFraction: editor.style.maxWidth,
                        selected: _selectedOverlay == CanvasManipTarget.caption,
                        onSelected: () {
                          setState(
                            () => _selectedOverlay = CanvasManipTarget.caption,
                          );
                          _styleBeforeGesture ??= editor.style;
                        },
                        onChanged: (nx, ny, scale) {
                          _styleBeforeGesture ??= editor.style;
                          ref
                              .read(editorControllerProvider.notifier)
                              .patchStyleLive(
                                editor.style.copyWith(
                                  positionX: nx,
                                  positionY: ny,
                                  fontSize: scale,
                                ),
                              );
                        },
                        onCommit: (nx, ny, scale) {
                          final before =
                              _styleBeforeGesture ?? editor.style;
                          final after = before.copyWith(
                            positionX: nx,
                            positionY: ny,
                            fontSize: scale,
                          );
                          ref
                              .read(editorControllerProvider.notifier)
                              .commitStyleGesture(before, after);
                          _styleBeforeGesture = null;
                        },
                        child: AnimatedSubtitleWidget(
                          key: ValueKey(active.id),
                          text: active.text,
                          style: editor.textTracking && sticker != null
                              ? FeatureOps.textTrackingFollow(
                                  editor.style,
                                  x: sticker.x,
                                  y: (sticker.y + 0.12).clamp(0.1, 0.9),
                                )
                              : editor.style,
                          animation: editor.animation,
                          videoSize: size,
                          sourceSize: Size(
                            editor.video.width.toDouble().clamp(1, 8192),
                            editor.video.height.toDouble().clamp(1, 8192),
                          ),
                          positioned: false,
                        ),
                      ),
                    if (sticker != null)
                      CanvasManipulator(
                        canvasSize: size,
                        nx: sticker.x,
                        ny: sticker.y,
                        scale: sticker.scale,
                        minScale: 0.4,
                        maxScale: 3.0,
                        maxWidthFraction: 0.5,
                        selected:
                            _selectedOverlay == CanvasManipTarget.sticker,
                        onSelected: () {
                          setState(
                            () =>
                                _selectedOverlay = CanvasManipTarget.sticker,
                          );
                          _stickerBeforeGesture ??= sticker;
                        },
                        onChanged: (nx, ny, scale) {
                          final live = sticker;
                          if (live == null) return;
                          _stickerBeforeGesture ??= live;
                          ref
                              .read(editorControllerProvider.notifier)
                              .patchStickerLive(
                                live.copyWith(x: nx, y: ny, scale: scale),
                              );
                        },
                        onCommit: (nx, ny, scale) {
                          final live = sticker;
                          if (live == null) return;
                          final before = _stickerBeforeGesture ?? live;
                          final after =
                              before.copyWith(x: nx, y: ny, scale: scale);
                          ref
                              .read(editorControllerProvider.notifier)
                              .commitStickerGesture(before, after);
                          _stickerBeforeGesture = null;
                        },
                        child: Opacity(
                          opacity: sticker.opacity.clamp(0.15, 1.0),
                          child: Transform.rotate(
                            angle: sticker.rotationDeg * 3.14159 / 180,
                            child: Text(
                              sticker.emoji,
                              style: TextStyle(
                                fontSize: SubtitleLayout.stickerBaseSize(
                                      editor.video.height
                                          .toDouble()
                                          .clamp(1, 8192),
                                    ) *
                                    (size.height /
                                        editor.video.height
                                            .toDouble()
                                            .clamp(1, 8192)) *
                                    sticker.scale,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (clip != null && clip.maskType == 'circle')
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CircleMaskPainter(),
                          size: size,
                        ),
                      ),
                    if (clip != null && clip.chromaKey)
                      IgnorePointer(
                        child: ColoredBox(
                          color: const Color(0x3300FF00),
                        ),
                      ),
                    if (editor.watermarkText.trim().isNotEmpty)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Opacity(
                          opacity: 0.55,
                          child: Text(
                            editor.watermarkText.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static List<double> _bcsMatrix(double b, double c, double s) {
    final t = (1 - c) / 2;
    final sr = (1 - s) * 0.3086;
    final sg = (1 - s) * 0.6094;
    final sb = (1 - s) * 0.0820;
    return <double>[
      c * (sr + s), c * sg, c * sb, 0, t * 255 + (b - 1) * 40,
      c * sr, c * (sg + s), c * sb, 0, t * 255 + (b - 1) * 40,
      c * sr, c * sg, c * (sb + s), 0, t * 255 + (b - 1) * 40,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _warmMatrix(double b, double c, double s) {
    final m = _bcsMatrix(b, c, s);
    m[0] += 0.08;
    m[8] -= 0.05;
    return m;
  }

  static List<double> _coolMatrix(double b, double c, double s) {
    final m = _bcsMatrix(b, c, s);
    m[0] -= 0.05;
    m[8] += 0.08;
    return m;
  }
}

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.shortestSide * 0.85,
          height: size.shortestSide * 0.85,
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}