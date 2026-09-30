class VideoMetadata {
  const VideoMetadata({
    required this.path,
    required this.fileName,
    required this.duration,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.thumbnailPath,
  });

  final String path;
  final String fileName;
  final Duration duration;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String? thumbnailPath;

  double get aspectRatio =>
      width == 0 || height == 0 ? 16 / 9 : width / height;

  String get resolutionLabel => '${width}x$height';

  String get fileSizeLabel {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  VideoMetadata copyWith({String? thumbnailPath}) {
    return VideoMetadata(
      path: path,
      fileName: fileName,
      duration: duration,
      width: width,
      height: height,
      fileSizeBytes: fileSizeBytes,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}
