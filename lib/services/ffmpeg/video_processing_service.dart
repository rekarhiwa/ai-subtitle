import '../../models/export_quality.dart';
import '../../models/video_metadata.dart';

typedef ProgressCallback = void Function(double progress, String message);

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

  Future<void> cancelProcessing();

  Future<bool> isAvailable();
}
