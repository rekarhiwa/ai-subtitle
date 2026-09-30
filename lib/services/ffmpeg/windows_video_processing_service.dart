import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../models/export_quality.dart';
import '../../models/video_metadata.dart';
import 'video_processing_service.dart';

/// Windows implementation using a bundled/local FFmpeg executable + Process.
class WindowsVideoProcessingService implements VideoProcessingService {
  WindowsVideoProcessingService({
    String? ffmpegPath,
    String? ffprobePath,
  })  : _ffmpegOverride = ffmpegPath,
        _ffprobeOverride = ffprobePath;

  final String? _ffmpegOverride;
  final String? _ffprobeOverride;
  final _log = Logger('WindowsVideoProcessingService');

  Process? _active;
  bool _cancelled = false;

  Future<String> _resolveFfmpeg() async {
    final override = _ffmpegOverride;
    if (override != null && await File(override).exists()) {
      return override;
    }

    final candidates = <String>[
      p.normalize(
        p.join(Directory.current.path, AppConfig.windowsFfmpegRelativePath),
      ),
      p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'data',
          'flutter_assets',
          AppConfig.windowsFfmpegRelativePath,
        ),
      ),
      p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'ffmpeg.exe',
        ),
      ),
      'ffmpeg',
    ];

    for (final c in candidates) {
      if (c == 'ffmpeg') {
        final result = await Process.run('where', ['ffmpeg']);
        if (result.exitCode == 0) return 'ffmpeg';
        continue;
      }
      if (await File(c).exists()) return c;
    }
    throw AppException.missingFfmpeg();
  }

  Future<String> _resolveFfprobe() async {
    final override = _ffprobeOverride;
    if (override != null && await File(override).exists()) {
      return override;
    }
    final candidates = <String>[
      p.normalize(
        p.join(Directory.current.path, AppConfig.windowsFfprobeRelativePath),
      ),
      p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'ffprobe.exe',
        ),
      ),
      'ffprobe',
    ];
    for (final c in candidates) {
      if (c == 'ffprobe') {
        final result = await Process.run('where', ['ffprobe']);
        if (result.exitCode == 0) return 'ffprobe';
        continue;
      }
      if (await File(c).exists()) return c;
    }
    // Fall back to ffmpeg - we can still probe with ffmpeg in some cases.
    return _resolveFfmpeg();
  }

  @override
  Future<bool> isAvailable() async {
    try {
      await _resolveFfmpeg();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    ProgressCallback? onProgress,
    Duration? totalDuration,
  }) async {
    _cancelled = false;
    _log.info('Running: $executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      runInShell: false,
    );
    _active = process;

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    process.stdout.transform(utf8.decoder).listen((data) {
      stdoutBuffer.write(data);
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
      if (onProgress != null && totalDuration != null) {
        final match = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(data);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = double.parse(match.group(3)!);
          final current = Duration(
            hours: h,
            minutes: m,
            milliseconds: (s * 1000).round(),
          );
          final progress = (current.inMilliseconds /
                  totalDuration.inMilliseconds.clamp(1, 1 << 62))
              .clamp(0.0, 0.99);
          onProgress(progress, 'Processing…');
        }
      }
    });

    final code = await process.exitCode;
    _active = null;
    if (_cancelled) throw AppException.exportCancelled();
    return ProcessResult(
      process.pid,
      code,
      stdoutBuffer.toString(),
      stderrBuffer.toString(),
    );
  }

  @override
  Future<void> cancelProcessing() async {
    _cancelled = true;
    _active?.kill(ProcessSignal.sigkill);
    _active = null;
  }

  @override
  Future<VideoMetadata> getVideoMetadata(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      throw AppException.unsupportedVideo();
    }

    final ffprobe = await _resolveFfprobe();
    final result = await _run(ffprobe, [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      videoPath,
    ]);

    if (result.exitCode != 0) {
      throw AppException.unsupportedVideo();
    }

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final streams = (json['streams'] as List?) ?? const [];
    Map<String, dynamic>? videoStream;
    for (final s in streams) {
      if (s is Map && s['codec_type'] == 'video') {
        videoStream = Map<String, dynamic>.from(s);
        break;
      }
    }
    if (videoStream == null) throw AppException.unsupportedVideo();

    final format = Map<String, dynamic>.from(json['format'] as Map? ?? {});
    final durationSec = double.tryParse('${format['duration']}') ??
        double.tryParse('${videoStream['duration']}') ??
        0;
    final width = int.tryParse('${videoStream['width']}') ?? 0;
    final height = int.tryParse('${videoStream['height']}') ?? 0;
    final size = int.tryParse('${format['size']}') ?? await file.length();

    return VideoMetadata(
      path: videoPath,
      fileName: p.basename(videoPath),
      duration: Duration(milliseconds: (durationSec * 1000).round()),
      width: width,
      height: height,
      fileSizeBytes: size,
    );
  }

  @override
  Future<String> generateThumbnail({
    required String videoPath,
    required String outputPath,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    final result = await _run(ffmpeg, [
      '-y',
      '-ss',
      '00:00:01.000',
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-q:v',
      '3',
      outputPath,
    ]);
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      // Retry at 0s for very short clips.
      final retry = await _run(ffmpeg, [
        '-y',
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-q:v',
        '3',
        outputPath,
      ]);
      if (retry.exitCode != 0) {
        throw AppException.ffmpegFailed('Could not generate thumbnail');
      }
    }
    return outputPath;
  }

  @override
  Future<String> extractAudio({
    required String videoPath,
    required String outputPath,
    ProgressCallback? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    onProgress?.call(0.05, 'Extracting audio…');
    final meta = await getVideoMetadata(videoPath);
    final result = await _run(
      ffmpeg,
      [
        '-y',
        '-i',
        videoPath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'aac',
        '-b:a',
        '64k',
        outputPath,
      ],
      onProgress: onProgress,
      totalDuration: meta.duration,
    );
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      throw AppException.audioExtractionFailed(
        (result.stderr as String).split('\n').last.trim(),
      );
    }
    onProgress?.call(1.0, 'Audio ready');
    return outputPath;
  }

  @override
  Future<String> burnSubtitles({
    required String videoPath,
    required String assPath,
    required String outputPath,
    required ExportQuality quality,
    String? fontsDir,
    ProgressCallback? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    final meta = await getVideoMetadata(videoPath);
    onProgress?.call(0.02, 'Burning subtitles…');

    // Escape path for ass filter on Windows.
    final escapedAss = assPath
        .replaceAll(r'\', r'/')
        .replaceAll(':', r'\:')
        .replaceAll("'", r"\'");

    var filter = "ass='$escapedAss'";
    if (fontsDir != null && fontsDir.isNotEmpty) {
      final escapedFonts = fontsDir
          .replaceAll(r'\', r'/')
          .replaceAll(':', r'\:')
          .replaceAll("'", r"\'");
      filter = "ass='$escapedAss':fontsdir='$escapedFonts'";
    }

    final result = await _run(
      ffmpeg,
      [
        '-y',
        '-i',
        videoPath,
        '-vf',
        filter,
        '-c:v',
        'libx264',
        '-preset',
        quality.preset,
        '-crf',
        '${quality.crf}',
        '-c:a',
        'copy',
        '-movflags',
        '+faststart',
        outputPath,
      ],
      onProgress: onProgress,
      totalDuration: meta.duration,
    );

    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      // Fallback: subtitles filter (libass) with force_style omitted.
      final fallbackFilter = fontsDir == null
          ? "subtitles='${assPath.replaceAll(r'\', r'/').replaceAll(':', r'\:')}'"
          : "subtitles='${assPath.replaceAll(r'\', r'/').replaceAll(':', r'\:')}':fontsdir='${fontsDir.replaceAll(r'\', r'/').replaceAll(':', r'\:')}'";
      final retry = await _run(
        ffmpeg,
        [
          '-y',
          '-i',
          videoPath,
          '-vf',
          fallbackFilter,
          '-c:v',
          'libx264',
          '-preset',
          quality.preset,
          '-crf',
          '${quality.crf}',
          '-c:a',
          'copy',
          '-movflags',
          '+faststart',
          outputPath,
        ],
        onProgress: onProgress,
        totalDuration: meta.duration,
      );
      if (retry.exitCode != 0 || !await File(outputPath).exists()) {
        throw AppException.ffmpegFailed(
          (retry.stderr as String).split('\n').where((l) => l.trim().isNotEmpty).lastOrNull ??
              'subtitle burn-in failed',
        );
      }
    }
    onProgress?.call(1.0, 'Export complete');
    return outputPath;
  }
}
