import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../models/export_quality.dart';
import '../../models/video_metadata.dart';
import 'video_processing_service.dart';

/// Android implementation using maintained ffmpeg_kit_flutter_new.
class AndroidVideoProcessingService implements VideoProcessingService {
  final _log = Logger('AndroidVideoProcessingService');
  bool _cancelled = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> cancelProcessing() async {
    _cancelled = true;
    await FFmpegKit.cancel();
  }

  Future<void> _ensureNotCancelled() async {
    if (_cancelled) throw AppException.exportCancelled();
  }

  /// Quotes paths for FFmpegKit argument parsing.
  String _q(String path) => '"${path.replaceAll('"', r'\"')}"';

  String _usefulError(String? logs) {
    if (logs == null || logs.trim().isEmpty) {
      return 'Unknown FFmpeg error';
    }
    final lines = logs
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final interesting = lines.where((l) {
      final lower = l.toLowerCase();
      if (lower.startsWith('ffmpeg version')) return false;
      if (lower.startsWith('built with')) return false;
      if (lower.startsWith('configuration:')) return false;
      if (RegExp(r'^lib\w+\s+\d').hasMatch(lower)) return false;
      return lower.contains('error') ||
          lower.contains('failed') ||
          lower.contains('invalid') ||
          lower.contains('no such') ||
          lower.contains('unknown') ||
          lower.contains('does not contain') ||
          lower.contains('permission') ||
          lower.startsWith('[');
    }).toList();

    if (interesting.isNotEmpty) {
      return interesting.take(3).join(' | ');
    }
    return lines.length <= 3
        ? lines.join(' | ')
        : lines.sublist(lines.length - 3).join(' | ');
  }

  /// Runs FFmpeg and waits until the session completes.
  /// [executeAsync] alone returns before work finishes — we must await a Completer.
  Future<FFmpegSession> _run(
    String command, {
    ProgressCallback? onProgress,
    int? totalMs,
  }) async {
    _log.info('FFmpeg: $command');
    final done = Completer<FFmpegSession>();

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        if (!done.isCompleted) done.complete(session);
      },
      (log) {
        final msg = log.getMessage();
        if (msg.trim().isNotEmpty) {
          _log.fine(msg);
        }
      },
      (Statistics stats) {
        if (onProgress == null || totalMs == null || totalMs <= 0) return;
        final progress = (stats.getTime() / totalMs).clamp(0.0, 0.99);
        onProgress(progress, 'Processing…');
      },
    );

    final session = await done.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () {
        throw AppException.ffmpegFailed('Timed out while processing media');
      },
    );
    await _ensureNotCancelled();
    return session;
  }

  Future<bool> _succeeded(FFmpegSession session, String outputPath) async {
    final code = await session.getReturnCode();
    if (ReturnCode.isCancel(code)) {
      throw AppException.exportCancelled();
    }
    return ReturnCode.isSuccess(code) && await File(outputPath).exists();
  }

  @override
  Future<VideoMetadata> getVideoMetadata(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) throw AppException.unsupportedVideo();

    final session = await FFprobeKit.getMediaInformation(videoPath);
    final info = session.getMediaInformation();
    if (info == null) throw AppException.unsupportedVideo();

    final allProperties = info.getAllProperties() ?? {};
    final streams = (allProperties['streams'] as List?) ?? const [];
    Map<String, dynamic>? videoStream;
    for (final s in streams) {
      if (s is Map && s['codec_type'] == 'video') {
        videoStream = Map<String, dynamic>.from(s);
        break;
      }
    }
    if (videoStream == null) throw AppException.unsupportedVideo();

    final durationSec = double.tryParse('${info.getDuration()}') ?? 0;
    final width = int.tryParse('${videoStream['width']}') ?? 0;
    final height = int.tryParse('${videoStream['height']}') ?? 0;
    final size = int.tryParse('${info.getSize()}') ?? await file.length();

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
    _cancelled = false;
    final session = await FFmpegKit.execute(
      '-y -ss 00:00:01.000 -i ${_q(videoPath)} -frames:v 1 -q:v 3 ${_q(outputPath)}',
    );
    if (!await _succeeded(session, outputPath)) {
      final retry = await FFmpegKit.execute(
        '-y -i ${_q(videoPath)} -frames:v 1 -q:v 3 ${_q(outputPath)}',
      );
      if (!await _succeeded(retry, outputPath)) {
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
    _cancelled = false;
    onProgress?.call(0.05, 'Extracting audio…');
    final meta = await getVideoMetadata(videoPath);
    final totalMs = meta.duration.inMilliseconds.clamp(1, 1 << 62);

    // Prefer AAC in M4A; fall back to MP3 if AAC encoder is unavailable.
    final attempts = <String>[
      '-y -i ${_q(videoPath)} -vn -ac 1 -ar 16000 -c:a aac -b:a 64k ${_q(outputPath)}',
      '-y -i ${_q(videoPath)} -vn -ac 1 -ar 16000 -c:a libmp3lame -b:a 64k ${_q(outputPath.replaceAll('.m4a', '.mp3'))}',
      '-y -i ${_q(videoPath)} -vn -ac 1 -ar 16000 -f wav ${_q(outputPath.replaceAll('.m4a', '.wav'))}',
    ];

    String? lastError;
    for (var i = 0; i < attempts.length; i++) {
      final cmd = attempts[i];
      final out = i == 0
          ? outputPath
          : i == 1
              ? outputPath.replaceAll('.m4a', '.mp3')
              : outputPath.replaceAll('.m4a', '.wav');

      try {
        final session = await _run(
          cmd,
          onProgress: (p, _) => onProgress?.call(0.05 + p * 0.9, 'Extracting audio…'),
          totalMs: totalMs,
        );
        if (await _succeeded(session, out)) {
          onProgress?.call(1.0, 'Audio ready');
          return out;
        }
        lastError = _usefulError(await session.getAllLogsAsString());
      } on AppException {
        rethrow;
      } catch (e) {
        lastError = e.toString();
      }
    }

    throw AppException.audioExtractionFailed(lastError);
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
    _cancelled = false;
    onProgress?.call(0.02, 'Burning subtitles…');
    final meta = await getVideoMetadata(videoPath);
    final totalMs = meta.duration.inMilliseconds.clamp(1, 1 << 62);

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

    final cmd =
        '-y -i ${_q(videoPath)} -vf "$filter" -c:v libx264 -preset ${quality.preset} '
        '-crf ${quality.crf} -c:a copy -movflags +faststart ${_q(outputPath)}';

    final session = await _run(
      cmd,
      onProgress: (p, _) => onProgress?.call(p, 'Burning subtitles…'),
      totalMs: totalMs,
    );

    if (!await _succeeded(session, outputPath)) {
      final fallback =
          '-y -i ${_q(videoPath)} -vf "subtitles=\'$escapedAss\'" -c:v libx264 '
          '-preset ${quality.preset} -crf ${quality.crf} -c:a copy '
          '-movflags +faststart ${_q(outputPath)}';
      final retry = await _run(
        fallback,
        onProgress: (p, _) => onProgress?.call(p, 'Burning subtitles…'),
        totalMs: totalMs,
      );
      if (!await _succeeded(retry, outputPath)) {
        throw AppException.ffmpegFailed(
          _usefulError(await retry.getAllLogsAsString()),
        );
      }
    }
    onProgress?.call(1.0, 'Export complete');
    return outputPath;
  }
}
