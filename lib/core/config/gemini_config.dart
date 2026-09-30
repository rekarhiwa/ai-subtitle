/// Central Gemini API configuration.
/// Change [model] here to switch models project-wide.
class GeminiConfig {
  GeminiConfig._();

  /// Model used for audio transcription with timestamps.
  /// Update this single value when Google releases a better speech model.
  static const String model = 'gemini-3.8-flash';

  static const String baseUrl = 'https://generativelanguage.googleapis.com';

  static const String apiVersion = 'v1beta';

  /// Prefer Files API when audio exceeds this size (bytes).
  static const int inlineUploadMaxBytes = 15 * 1024 * 1024;

  static const int maxRetries = 3;

  static const Duration retryDelay = Duration(seconds: 2);

  static const Duration requestTimeout = Duration(minutes: 5);

  static String generateContentUrl(String modelName) =>
      '$baseUrl/$apiVersion/models/$modelName:generateContent';

  static String filesUploadUrl() => '$baseUrl/upload/$apiVersion/files';

  static String filesUrl() => '$baseUrl/$apiVersion/files';
}
