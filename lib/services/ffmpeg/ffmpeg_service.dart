import 'package:ai_subtitle/models/export_quality.dart';
import 'package:ai_subtitle/models/video_metadata.dart';
import 'dart:io';

import 'android_video_processing_service.dart';
import 'video_processing_service.dart';
import 'windows_video_processing_service.dart';

/// Facade used by UI / providers. Picks the platform implementation.
class FFmpegService implements VideoProcessingService {
  FFmpegService({VideoProcessingService? delegate})
      : _delegate = delegate ?? _createDefault();

  final VideoProcessingService _delegate;

  static VideoProcessingService _createDefault() {
    if (Platform.isWindows) {
      return WindowsVideoProcessingService();
    }
    if (Platform.isAndroid) {
      return AndroidVideoProcessingService();
    }
    // Future iOS/macOS: plug platform services here.
    return WindowsVideoProcessingService();
  }

  VideoProcessingService get implementation => _delegate;

  @override
  Future<bool> isAvailable() => _delegate.isAvailable();

  @override
  Future<void> cancelProcessing() => _delegate.cancelProcessing();

  @override
  Future<VideoMetadata> getVideoMetadata(String videoPath) =>
      _delegate.getVideoMetadata(videoPath);

  @override
  Future<String> generateThumbnail({
    required String videoPath,
    required String outputPath,
  }) =>
      _delegate.generateThumbnail(
        videoPath: videoPath,
        outputPath: outputPath,
      );

  @override
  Future<String> extractAudio({
    required String videoPath,
    required String outputPath,
    ProgressCallback? onProgress,
  }) =>
      _delegate.extractAudio(
        videoPath: videoPath,
        outputPath: outputPath,
        onProgress: onProgress,
      );

  @override
  Future<String> burnSubtitles({
    required String videoPath,
    required String assPath,
    required String outputPath,
    required ExportQuality quality,
    String? fontsDir,
    ProgressCallback? onProgress,
  }) =>
      _delegate.burnSubtitles(
        videoPath: videoPath,
        assPath: assPath,
        outputPath: outputPath,
        quality: quality,
        fontsDir: fontsDir,
        onProgress: onProgress,
      );

  @override
  Future<String> trimAndConcat({
    required List<TimelineSegmentSpec> segments,
    required String outputPath,
    required ExportQuality quality,
    required String workDir,
    ProgressCallback? onProgress,
  }) =>
      _delegate.trimAndConcat(
        segments: segments,
        outputPath: outputPath,
        quality: quality,
        workDir: workDir,
        onProgress: onProgress,
      );

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
  }) =>
      _delegate.mixBackgroundAudio(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
        videoVolume: videoVolume,
        audioVolume: audioVolume,
        audioDelay: audioDelay,
        muteOriginal: muteOriginal,
        onProgress: onProgress,
      );

  @override
  Future<String> generateTone({
    required String lavfiSource,
    required String outputPath,
    ProgressCallback? onProgress,
  }) =>
      _delegate.generateTone(
        lavfiSource: lavfiSource,
        outputPath: outputPath,
        onProgress: onProgress,
      );

  @override
  Future<String> exportGif({
    required String videoPath,
    required String outputPath,
    Duration start = Duration.zero,
    Duration duration = const Duration(seconds: 3),
    int width = 480,
    ProgressCallback? onProgress,
  }) =>
      _delegate.exportGif(
        videoPath: videoPath,
        outputPath: outputPath,
        start: start,
        duration: duration,
        width: width,
        onProgress: onProgress,
      );
}
