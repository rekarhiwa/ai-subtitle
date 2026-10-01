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

    final escapedAss = assPath
        .replaceAll(r'\', r'/')
        .replaceAll(':', r'\:')
        .replaceAll("'", r"\'");

    String? escapedFonts;
    if (fontsDir != null && fontsDir.isNotEmpty) {
      escapedFonts = fontsDir
          .replaceAll(r'\', r'/')
          .replaceAll(':', r'\:')
          .replaceAll("'", r"\'");
    }

    final filters = <String>[
      if (escapedFonts != null) "ass='$escapedAss':fontsdir='$escapedFonts'",
      "ass='$escapedAss'",
      if (escapedFonts != null)
        "subtitles='$escapedAss':fontsdir='$escapedFonts'",
      "subtitles='$escapedAss'",
    ];

    Object? lastError;
    for (final filter in filters) {
      if (_cancelled) throw AppException.exportCancelled();
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
          'aac',
          '-b:a',
          '128k',
          '-movflags',
          '+faststart',
          outputPath,
        ],
        onProgress: onProgress,
        totalDuration: meta.duration,
      );
      if (result.exitCode == 0 && await File(outputPath).exists()) {
        onProgress?.call(1.0, 'Export complete');
        return outputPath;
      }
      lastError = (result.stderr as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .lastOrNull;
      _log.warning('Burn filter failed ($filter): $lastError');
    }

    throw AppException.ffmpegFailed(
      lastError?.toString() ?? 'subtitle burn-in failed',
    );
  }

  @override
  Future<String> trimAndConcat({
    required List<TimelineSegmentSpec> segments,
    required String outputPath,
    required ExportQuality quality,
    required String workDir,
    ProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    if (segments.isEmpty) {
      throw AppException.ffmpegFailed('No video clips to export');
    }
    final ffmpeg = await _resolveFfmpeg();
    onProgress?.call(0.02, 'Preparing clips…');
    final partPaths = <String>[];
    for (var i = 0; i < segments.length; i++) {
      if (_cancelled) throw AppException.exportCancelled();
      final seg = segments[i];
      final part = p.join(workDir, 'part_$i.mp4');
      final ss = (seg.inPoint.inMilliseconds / 1000.0).toStringAsFixed(3);
      final to = (seg.outPoint.inMilliseconds / 1000.0).toStringAsFixed(3);
      final result = await _run(
        ffmpeg,
        [
          '-y',
          '-ss',
          ss,
          '-to',
          to,
          '-i',
          seg.path,
          '-c:v',
          'libx264',
          '-preset',
          quality.preset,
          '-crf',
          '${quality.crf}',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-movflags',
          '+faststart',
          part,
        ],
        onProgress: (pr, _) => onProgress?.call(
          0.05 + (i + pr) / segments.length * 0.7,
          'Encoding clip ${i + 1}/${segments.length}…',
        ),
        totalDuration: seg.outPoint - seg.inPoint,
      );
      if (result.exitCode != 0 || !await File(part).exists()) {
        throw AppException.ffmpegFailed('Failed encoding clip ${i + 1}');
      }
      partPaths.add(part);
    }

    if (partPaths.length == 1) {
      await File(partPaths.first).copy(outputPath);
      onProgress?.call(1.0, 'Clips ready');
      return outputPath;
    }

    onProgress?.call(0.8, 'Concatenating…');
    final listFile = p.join(workDir, 'concat.txt');
    final listBody =
        partPaths.map((e) => "file '${e.replaceAll(r'\', '/')}'").join('\n');
    await File(listFile).writeAsString(listBody, flush: true);
    var result = await _run(
      ffmpeg,
      [
        '-y',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        listFile,
        '-c',
        'copy',
        outputPath,
      ],
    );
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      result = await _run(
        ffmpeg,
        [
          '-y',
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          listFile,
          '-c:v',
          'libx264',
          '-preset',
          quality.preset,
          '-crf',
          '${quality.crf}',
          '-c:a',
          'aac',
          '-movflags',
          '+faststart',
          outputPath,
        ],
      );
      if (result.exitCode != 0 || !await File(outputPath).exists()) {
        throw AppException.ffmpegFailed('Concat failed');
      }
    }
    onProgress?.call(1.0, 'Clips ready');
    return outputPath;
  }

  @override
  Future<String> mixBackgroundAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    double videoVolume = 1.0,
    double audioVolume = 0.8,
    Duration audioDelay = Duration.zero,
    bool muteOriginal = false,
    ProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    final ffmpeg = await _resolveFfmpeg();
    onProgress?.call(0.05, 'Mixing audio…');
    final delayMs = audioDelay.inMilliseconds;
    final filter = muteOriginal
        ? '[1:a]volume=$audioVolume,adelay=$delayMs|$delayMs[aout]'
        : '[0:a]volume=$videoVolume[a0];[1:a]volume=$audioVolume,adelay=$delayMs|$delayMs[a1];'
            '[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[aout]';
    final result = await _run(
      ffmpeg,
      [
        '-y',
        '-i',
        videoPath,
        '-i',
        audioPath,
        '-filter_complex',
        filter,
        '-map',
        '0:v',
        '-map',
        '[aout]',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-b:a',
        '160k',
        '-shortest',
        '-movflags',
        '+faststart',
        outputPath,
      ],
      onProgress: onProgress,
    );
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      throw AppException.ffmpegFailed('Audio mix failed');
    }
    onProgress?.call(1.0, 'Audio mixed');
    return outputPath;
  }

  @override
  Future<String> generateTone({
    required String lavfiSource,
    required String outputPath,
    ProgressCallback? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    onProgress?.call(0.1, 'Generating tone…');
    final result = await _run(
      ffmpeg,
      [
        '-y',
        '-f',
        'lavfi',
        '-i',
        lavfiSource,
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        outputPath,
      ],
      onProgress: onProgress,
    );
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      throw AppException.ffmpegFailed('Tone generation failed');
    }
    onProgress?.call(1.0, 'Tone ready');
    return outputPath;
  }

  @override
  Future<String> exportGif({
    required String videoPath,
    required String outputPath,
    Duration start = Duration.zero,
    Duration duration = const Duration(seconds: 3),
    int width = 480,
    ProgressCallback? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    onProgress?.call(0.05, 'Exporting GIF…');
    final ss = (start.inMilliseconds / 1000.0).toStringAsFixed(2);
    final t = (duration.inMilliseconds / 1000.0).toStringAsFixed(2);
    final result = await _run(
      ffmpeg,
      [
        '-y',
        '-ss',
        ss,
        '-t',
        t,
        '-i',
        videoPath,
        '-vf',
        'fps=12,scale=$width:-1:flags=lanczos',
        '-loop',
        '0',
        outputPath,
      ],
      onProgress: onProgress,
      totalDuration: duration,
    );
    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      throw AppException.ffmpegFailed('GIF export failed');
    }
    onProgress?.call(1.0, 'GIF ready');
    return outputPath;
  }
}
