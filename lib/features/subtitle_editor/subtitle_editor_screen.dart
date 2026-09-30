import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import '../../models/subtitle_segment.dart';
import '../subtitle_animations/animated_subtitle_widget.dart';
import 'caption_timeline.dart';
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
  EditorTab _tab = EditorTab.text;
  bool _panelExpanded = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _posSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      final editor = ref.read(editorControllerProvider);
      if (editor == null) return;
      final active = SubtitleOps.activeAt(editor.segments, pos);
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
      await _player.open(Media(editor.video.path), play: false);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _seekTo(Duration d) async => _player.seek(d);

  Future<String?> _resolveFontsDir() async {
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

    final fileName =
        '${p.basenameWithoutExtension(editor.video.fileName)}_subtitled.mp4';

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
    final assPath = await temp.createPath(
      'burn_${DateTime.now().millisecondsSinceEpoch}.ass',
    );
    await File(assPath).writeAsString(
      export.toAss(
        segments: editor.segments,
        style: editor.style,
        videoWidth: editor.video.width,
        videoHeight: editor.video.height,
      ),
      flush: true,
    );

    final fontsDir = await _resolveFontsDir();
    final editorNotifier = ref.read(editorControllerProvider.notifier);
    try {
      editorNotifier.setExporting(
        isExporting: true,
        progress: 0.02,
        message: 'Rendering…',
        clearError: true,
      );
      await ffmpeg.burnSubtitles(
        videoPath: editor.video.path,
        assPath: assPath,
        outputPath: outPath,
        quality: editor.exportQuality,
        fontsDir: fontsDir,
        onProgress: (progress, message) {
          editorNotifier.setExporting(
            isExporting: true,
            progress: progress,
            message: message,
          );
        },
      );
      editorNotifier.setExporting(
        isExporting: false,
        progress: 1,
        message: 'Export complete',
        lastExportPath: outPath,
      );
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
      await temp.delete(assPath);
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
      position: _position,
      duration: editor.video.duration,
      activeId: active?.id ?? editor.activeSegmentId,
      thumbnailPath: editor.video.thumbnailPath,
      onSeek: _seekTo,
      onSelect: (s) async {
        notifier.setActiveSegment(s.id);
        await _seekTo(s.start);
      },
      onSegmentsChanged: notifier.setSegments,
      height: wide ? 180 : 168,
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
              onBack: () => Navigator.pop(context),
              onExport: () => _selectTab(EditorTab.export),
            ),
            if (editor.isExporting)
              LinearProgressIndicator(
                value: editor.exportProgress,
                minHeight: 2,
                color: AppColors.brand,
                backgroundColor: AppColors.surface,
              ),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              Expanded(child: _preview(editor, active)),
                              EditorTransport(
                                position: _position,
                                duration: editor.video.duration,
                                playing: _playing,
                                onPlayPause: () =>
                                    _playing ? _player.pause() : _player.play(),
                                onSeek: _seekTo,
                              ),
                              timeline,
                            ],
                          ),
                        ),
                        SizedBox(width: 360, child: toolPanel),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: _preview(editor, active)),
                        EditorTransport(
                          position: _position,
                          duration: editor.video.duration,
                          playing: _playing,
                          onPlayPause: () =>
                              _playing ? _player.pause() : _player.play(),
                          onSeek: _seekTo,
                        ),
                        timeline,
                        if (_panelExpanded)
                          SizedBox(
                            height: _tab == EditorTab.text ? 200 : 180,
                            child: toolPanel,
                          ),
                        EditorBottomDock(tab: _tab, onTab: _selectTab),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(EditorState editor, SubtitleSegment? active) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final videoAspect = editor.video.aspectRatio;
          var width = constraints.maxWidth;
          var height = width / videoAspect;
          if (height > constraints.maxHeight) {
            height = constraints.maxHeight;
            width = height * videoAspect;
          }
          final size = Size(width, height);
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(controller: _videoController),
                  if (active != null)
                    AnimatedSubtitleWidget(
                      text: active.text,
                      style: editor.style,
                      animation: editor.animation,
                      videoSize: size,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
