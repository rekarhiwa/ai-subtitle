import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
import '../montage/feature_ops.dart';
import '../montage/media_library.dart';
import '../subtitle_animations/animated_subtitle_widget.dart';
import 'caption_timeline.dart';
import 'clip_ops.dart';
import 'editor_tool_dock.dart';
import 'editor_top_bar.dart';
import 'editor_transport.dart';
import 'subtitle_ops.dart';

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
  bool _panelExpanded = false;
  String? _loadedMediaPath;
  String? _activeClipId;
  bool _seeking = false;
  DateTime _lastUiTick = DateTime.fromMillisecondsSinceEpoch(0);
  bool _advancingClip = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _posSub = _player.stream.position.listen((pos) {
      if (!mounted || _seeking || _advancingClip) return;
      final editor = ref.read(editorControllerProvider);
      if (editor == null) return;

      VideoClip? clip;
      if (_activeClipId != null) {
        clip = editor.videoClips.firstWhereOrNull((c) => c.id == _activeClipId);
      }
      clip ??= ClipOps.atPosition(editor.videoClips, _position) ??
          ClipOps.sorted(editor.videoClips).firstOrNull;

      Duration timelinePos;
      if (clip != null) {
        final intoSource = clip.reversed
            ? clip.outPoint - pos
            : pos - clip.inPoint;
        final intoMs =
            (intoSource.inMilliseconds / clip.speed.clamp(0.25, 4.0)).round();
        timelinePos = clip.timelineStart + Duration(milliseconds: intoMs);
        if (timelinePos < clip.timelineStart) timelinePos = clip.timelineStart;
        if (timelinePos > clip.timelineEnd) timelinePos = clip.timelineEnd;

        // Advance once when clip ends — avoid seek feedback loop.
        final nearEnd = clip.reversed
            ? pos <= clip.inPoint + const Duration(milliseconds: 60)
            : pos >= clip.outPoint - const Duration(milliseconds: 60);
        if (_playing && nearEnd) {
          final activeClip = clip;
          final next = ClipOps.sorted(editor.videoClips)
              .where((c) =>
                  c.timelineStart >=
                      activeClip.timelineEnd -
                          const Duration(milliseconds: 20))
              .where((c) => c.id != activeClip.id)
              .firstOrNull;
          if (next != null) {
            _advancingClip = true;
            _seekTo(next.timelineStart).whenComplete(() {
              _advancingClip = false;
            });
            return;
          }
        }
      } else {
        timelinePos = pos;
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

      final active = SubtitleOps.activeAt(editor.segments, clamped);
      if (active?.id != editor.activeSegmentId) {
        ref.read(editorControllerProvider.notifier).setActiveSegment(active?.id);
      }
    });
    _playSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final editor = ref.read(editorControllerProvider);
      if (editor == null) return;
      final first = ClipOps.sorted(editor.videoClips).firstOrNull;
      final path = first?.sourcePath ?? editor.video.path;
      await _player.open(Media(path), play: false);
      await _player.setRate(first?.speed.clamp(0.25, 4.0) ?? 1.0);
      _loadedMediaPath = path;
      _activeClipId = first?.id;
      if (first != null && first.inPoint > Duration.zero) {
        await _player.seek(first.inPoint);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _seekTo(Duration timelinePos) async {
    final editor = ref.read(editorControllerProvider);
    if (editor == null) return;
    _seeking = true;
    try {
      final clips = ClipOps.sorted(editor.videoClips);
      final clip = ClipOps.atPosition(clips, timelinePos) ??
          (clips.isNotEmpty ? clips.last : null);
      if (clip == null) {
        await _player.setRate(1.0);
        await _player.seek(timelinePos);
        if (mounted) setState(() => _position = timelinePos);
        return;
      }
      if (_loadedMediaPath != clip.sourcePath) {
        final wasPlaying = _playing;
        await _player.open(Media(clip.sourcePath), play: false);
        _loadedMediaPath = clip.sourcePath;
        if (wasPlaying) await _player.play();
      }
      _activeClipId = clip.id;
      ref.read(editorControllerProvider.notifier).setActiveClip(clip.id);
      await _player.setRate(clip.speed.clamp(0.25, 4.0));
      await _player.seek(ClipOps.sourceSeek(clip, timelinePos));
      if (mounted) setState(() => _position = timelinePos);
    } finally {
      _seeking = false;
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
        _panelExpanded = true;
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
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, fileName);
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

    late final String outPath;
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      outPath = p.join(dir.path, fileName);
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

    final temp = ref.read(tempFileServiceProvider);
    final export = ref.read(subtitleExportServiceProvider);
    final ffmpeg = ref.read(ffmpegServiceProvider);
    final editorNotifier = ref.read(editorControllerProvider.notifier);
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
      );

      final clips = ClipOps.sorted(editor.videoClips);
      final composedPath = p.join(workDir, 'composed.mp4');
      String videoForBurn = editor.video.path;

      final needsCompose = clips.length > 1 ||
          (clips.isNotEmpty &&
              (clips.first.inPoint > Duration.zero ||
                  clips.first.outPoint < clips.first.sourceDuration));

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
            );
          },
        );
        videoForBurn = composedPath;
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
            );
          },
        );
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
      );
      await File(assPath).writeAsString(assBody, flush: true);
      if (!await File(assPath).exists() || (await File(assPath).length()) < 50) {
        throw Exception('ASS subtitle file was not written correctly');
      }

      editorNotifier.setExporting(
        isExporting: true,
        progress: 0.55,
        message: 'Burning captions…',
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
          );
        },
      );

      if (!await File(outPath).exists()) {
        throw Exception('Export finished but output MP4 was not created');
      }

      editorNotifier.setExporting(
        isExporting: false,
        progress: 1,
        message: 'Export complete',
        lastExportPath: outPath,
      );
      await temp.delete(assPath);
      await _afterExport(outPath, share: Platform.isAndroid, isVideo: true);
    } catch (e) {
      editorNotifier.setExporting(
        isExporting: false,
        errorMessage: e.toString(),
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
    setState(() => _tab = EditorTab.audio);
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
    late final String outPath;
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      outPath = p.join(dir.path, fileName);
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
    final notifier = ref.read(editorControllerProvider.notifier);
    try {
      notifier.setExporting(
        isExporting: true,
        progress: 0.05,
        message: 'Exporting GIF…',
        clearError: true,
      );
      final path = await ref.read(ffmpegServiceProvider).exportGif(
            videoPath: editor.video.path,
            outputPath: outPath,
            start: _position,
            duration: const Duration(seconds: 3),
          );
      notifier.setExporting(isExporting: false, progress: 1, lastExportPath: path);
      await _afterExport(path, share: Platform.isAndroid);
    } catch (e) {
      notifier.setExporting(
        isExporting: false,
        errorMessage: e.toString(),
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

  void _selectTab(EditorTab tab) {
    setState(() {
      if (_tab == tab && _panelExpanded) {
        _panelExpanded = false;
      } else {
        _tab = tab;
        _panelExpanded = true;
      }
    });
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
                    Row(
                      children: [
                        for (final q in ExportQuality.values) ...[
                          if (q != ExportQuality.values.first)
                            const SizedBox(width: 8),
                          QualityChip(
                            label: q.label,
                            selected: live.exportQuality == q,
                            onTap: () => notifier.setExportQuality(q),
                          ),
                        ],
                      ],
                    ),
                    if (live.isExporting) ...[
                      const SizedBox(height: 14),
                      Text(
                        live.exportMessage.isEmpty
                            ? 'Rendering…'
                            : live.exportMessage,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: live.exportProgress.clamp(0.0, 1.0),
                          minHeight: 6,
                          color: AppColors.brand,
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
        await _seekTo(s.start);
      },
      onSelectClip: (c) async {
        notifier.setActiveClip(c.id);
        await _seekTo(c.timelineStart);
      },
      onSegmentsChanged: notifier.setSegments,
      onClipsChanged: notifier.setVideoClips,
      height: wide ? 188 : 172,
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
    );

    return Scaffold(
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
              onBack: () async {
                await notifier.persist();
                if (context.mounted) Navigator.pop(context);
              },
              onExport: () {
                if (wide) {
                  _selectTab(EditorTab.export);
                } else {
                  _showExportSheet(editor);
                }
              },
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
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _preview(editor, active),
                                        _previewQuickActions(editor),
                                      ],
                                    ),
                                  ),
                                  EditorTransport(
                                    position: _position,
                                    duration: editor.timelineDuration,
                                    playing: _playing,
                                    onPlayPause: () => _playing
                                        ? _player.pause()
                                        : _player.play(),
                                    onSeek: _seekTo,
                                  ),
                                  timeline,
                                ],
                              ),
                            ),
                            Container(
                              width: 360,
                              color: AppColors.surface,
                              child: toolPanel,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _preview(editor, active),
                                  _previewQuickActions(editor),
                                ],
                              ),
                            ),
                            EditorTransport(
                              position: _position,
                              duration: editor.timelineDuration,
                              playing: _playing,
                              onPlayPause: () =>
                                  _playing ? _player.pause() : _player.play(),
                              onSeek: _seekTo,
                            ),
                            timeline,
                            if (_panelExpanded)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                height: switch (_tab) {
                                  EditorTab.tools => 300,
                                  EditorTab.text => 280,
                                  EditorTab.animation => 220,
                                  EditorTab.export => 300,
                                  EditorTab.style => 280,
                                  EditorTab.edit => 320,
                                  EditorTab.audio => 280,
                                  EditorTab.stickers => 260,
                                  EditorTab.ai => 320,
                                },
                                decoration: const BoxDecoration(
                                  color: AppColors.surface,
                                  border: Border(
                                    top: BorderSide(
                                      color: Color(0xFF222222),
                                    ),
                                  ),
                                ),
                                child: toolPanel,
                              ),
                            EditorBottomDock(tab: _tab, onTab: _selectTab),
                          ],
                        ),
                  if (editor.isExporting)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.62),
                        child: Center(
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 22,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: CircularProgressIndicator(
                                    value: editor.exportProgress > 0.02
                                        ? editor.exportProgress
                                        : null,
                                    strokeWidth: 3,
                                    color: AppColors.playhead,
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
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${((editor.exportProgress.clamp(0, 1)) * 100).round()}%',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }

  Widget _previewQuickActions(EditorState editor) {
    return Positioned(
      right: 10,
      bottom: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _CapCutChip(
            icon: Icons.closed_caption_rounded,
            label: editor.segments.isEmpty ? 'Captions' : 'Re-caption',
            onTap: _runAutoCaptions,
          ),
          const SizedBox(height: 8),
          _CapCutChip(
            icon: Icons.add_rounded,
            label: 'Media',
            onTap: _addVideoClip,
          ),
          const SizedBox(height: 8),
          _CapCutChip(
            icon: Icons.music_note_rounded,
            label: 'Music',
            onTap: _addAudioClip,
          ),
        ],
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
                    if (active != null)
                      AnimatedSubtitleWidget(
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
                      ),
                    if (sticker != null)
                      Positioned(
                        left: sticker.x * width - 24 * sticker.scale,
                        top: sticker.y * height - 24 * sticker.scale,
                        child: Opacity(
                          opacity: sticker.opacity.clamp(0.15, 1.0),
                          child: Transform.rotate(
                            angle: sticker.rotationDeg * 3.14159 / 180,
                            child: Transform.scale(
                              scale: sticker.animated ? 1.08 : 1.0,
                              child: Text(
                                sticker.emoji,
                                style: TextStyle(fontSize: 40 * sticker.scale),
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

class _CapCutChip extends StatelessWidget {
  const _CapCutChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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