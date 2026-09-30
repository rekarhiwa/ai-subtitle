import 'dart:convert';

/// Defensive JSON extraction for LLM responses that may include markdown fences.
class JsonCleaner {
  JsonCleaner._();

  static Map<String, dynamic> parseObject(String raw) {
    final cleaned = clean(raw);
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object, got ${decoded.runtimeType}');
  }

  static String clean(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('Empty response');
    }

    // Strip ```json ... ``` or ``` ... ```
    final fence = RegExp(
      r'```(?:json|JSON)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    );
    final fenceMatch = fence.firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1)!.trim();
    }

    // If still wrapped with prose, extract outermost object.
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }

    return text.trim();
  }
}
