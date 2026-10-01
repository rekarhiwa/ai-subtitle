import '../../models/export_quality.dart';
import '../../models/video_metadata.dart';

typedef ProgressCallback = void Function(double progress, String message);

class TimelineSegmentSpec {
  const TimelineSegmentSpec({
    required this.path,
    required this.inPoint,
    required this.outPoint,
  });

  final String path;
  final Duration inPoint;
  final Duration outPoint;
}

/// Platform-agnostic video processing contract.
abstract class VideoProcessingService {
  Future<VideoMetadata> getVideoMetadata(String videoPath);

  Future<String> generateThumbnail({
    required String videoPath,
    required String outputPath,
  });

  Future<String> extractAudio({
    required String videoPath,
    required String outputPath,
    ProgressCallback? onProgress,
  });

  Future<String> burnSubtitles({
    required String videoPath,
    required String assPath,
    required String outputPath,
    required ExportQuality quality,
    String? fontsDir,
    ProgressCallback? onProgress,
  });

  /// Trim each segment then concat into one MP4 (re-encodes for reliability).
  Future<String> trimAndConcat({
    required List<TimelineSegmentSpec> segments,
    required String outputPath,
    required ExportQuality quality,
    required String workDir,
    ProgressCallback? onProgress,
  });

  /// Mix a background audio file onto a video (keeps video stream).
  Future<String> mixBackgroundAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    double videoVolume = 1.0,
    double audioVolume = 0.8,
    Duration audioDelay = Duration.zero,
    bool muteOriginal = false,
    ProgressCallback? onProgress,
  });

  /// Generate a short tone/SFX from lavfi (#21/#22).
  Future<String> generateTone({
    required String lavfiSource,
    required String outputPath,
    ProgressCallback? onProgress,
  });

  /// Export a short GIF preview from video (#131).
  Future<String> exportGif({
    required String videoPath,
    required String outputPath,
    Duration start = Duration.zero,
    Duration duration = const Duration(seconds: 3),
    int width = 480,
    ProgressCallback? onProgress,
  });

  Future<void> cancelProcessing();

  Future<bool> isAvailable();
}
