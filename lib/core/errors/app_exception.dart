/// User-facing application errors. Never expose stack traces through [message].
class AppException implements Exception {
  AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => message;

  factory AppException.noInternet() => AppException(
        'No internet connection. Check your network and try again.',
        code: 'no_internet',
      );

  factory AppException.invalidApiKey() => AppException(
        'Invalid Gemini API key. Open Settings and enter a valid key.',
        code: 'invalid_api_key',
      );

  factory AppException.quotaExceeded() => AppException(
        'Gemini quota exceeded. Wait a bit or check your Google AI Studio usage.',
        code: 'quota_exceeded',
      );

  factory AppException.audioExtractionFailed([String? detail]) => AppException(
        detail == null
            ? 'Audio extraction failed. The video may be unsupported or corrupted.'
            : 'Audio extraction failed: $detail',
        code: 'audio_extraction_failed',
      );

  factory AppException.unsupportedVideo() => AppException(
        'Unsupported video format. Please select an MP4 or similar media file.',
        code: 'unsupported_video',
      );

  factory AppException.notEnoughDiskSpace() => AppException(
        'Not enough disk space to continue processing.',
        code: 'disk_space',
      );

  factory AppException.transcriptionFailed([String? detail]) => AppException(
        detail == null
            ? 'Transcription failed. Please try again.'
            : 'Transcription failed: $detail',
        code: 'transcription_failed',
      );

  factory AppException.exportCancelled() => AppException(
        'Export cancelled.',
        code: 'export_cancelled',
      );

  factory AppException.ffmpegFailed([String? detail]) => AppException(
        detail == null
            ? 'FFmpeg failed while processing media.'
            : 'FFmpeg failed: $detail',
        code: 'ffmpeg_failed',
      );

  factory AppException.missingApiKey() => AppException(
        'Add your Gemini API key in Settings before generating subtitles.',
        code: 'missing_api_key',
      );

  factory AppException.missingFfmpeg() => AppException(
        'FFmpeg was not found. Place ffmpeg.exe in third_party/ffmpeg/windows/ '
        'or install FFmpeg and add it to PATH.',
        code: 'missing_ffmpeg',
      );

  factory AppException.fromGeminiStatus(int status, String body) {
    final lower = body.toLowerCase();
    if (status == 401 || status == 403 || lower.contains('api key')) {
      return AppException.invalidApiKey();
    }
    if (status == 429 || lower.contains('quota') || lower.contains('rate')) {
      return AppException.quotaExceeded();
    }
    return AppException.transcriptionFailed('HTTP $status');
  }
}
