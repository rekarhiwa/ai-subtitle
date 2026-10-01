class AppConfig {
  AppConfig._();

  static const String appName = 'Montage';
  static const String appTagline = 'مۆنتاژی ئاسان · ژێرنووسی کوردی';
  static const String tempFolderName = 'montage_temp';
  static const String defaultLanguageCode = 'ckb';
  static const String defaultLanguageLabel = 'Kurdish Sorani';

  /// Relative path (from project / install root) for bundled Windows FFmpeg.
  static const String windowsFfmpegRelativePath =
      'third_party/ffmpeg/windows/ffmpeg.exe';
  static const String windowsFfprobeRelativePath =
      'third_party/ffmpeg/windows/ffprobe.exe';
}
