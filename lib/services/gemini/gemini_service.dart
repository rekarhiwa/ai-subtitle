import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/config/gemini_config.dart';
import '../../core/errors/app_exception.dart';
import '../../models/transcription_result.dart';

class GeminiService {
  GeminiService({
    http.Client? client,
    String? promptAssetPath,
  })  : _client = client ?? http.Client(),
        _promptAssetPath =
            promptAssetPath ?? 'assets/prompts/transcription_prompt.txt';

  final http.Client _client;
  final String _promptAssetPath;
  final _log = Logger('GeminiService');

  String? _cachedPrompt;

  Future<String> _loadPrompt() async {
    if (_cachedPrompt != null) return _cachedPrompt!;
    _cachedPrompt = await rootBundle.loadString(_promptAssetPath);
    return _cachedPrompt!;
  }

  Future<bool> validateApiKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
    try {
      final uri = Uri.parse(
        '${GeminiConfig.baseUrl}/${GeminiConfig.apiVersion}/models'
        '?key=$key&pageSize=1',
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) return true;
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        return false;
      }
      // Transient errors — treat as unknown; still allow user to proceed.
      _log.warning('API key check HTTP ${response.statusCode}');
      return response.statusCode < 500;
    } on SocketException {
      throw AppException.noInternet();
    } on http.ClientException {
      throw AppException.noInternet();
    }
  }

  Future<TranscriptionResult> transcribeAudio({
    required String apiKey,
    required String audioPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw AppException.missingApiKey();

    final file = File(audioPath);
    if (!await file.exists()) {
      throw AppException.transcriptionFailed('Audio file missing');
    }

    final prompt = await _loadPrompt();
    final size = await file.length();
    final mimeType = _mimeFor(audioPath);

    Object? lastError;
    for (var attempt = 1; attempt <= GeminiConfig.maxRetries; attempt++) {
      try {
        onProgress?.call(0.1, 'Uploading audio…');
        final text = size <= GeminiConfig.inlineUploadMaxBytes
            ? await _transcribeInline(
                apiKey: key,
                audioPath: audioPath,
                mimeType: mimeType,
                prompt: prompt,
                onProgress: onProgress,
              )
            : await _transcribeViaFilesApi(
                apiKey: key,
                audioPath: audioPath,
                mimeType: mimeType,
                prompt: prompt,
                onProgress: onProgress,
              );

        onProgress?.call(0.9, 'Preparing timeline…');
        return TranscriptionResult.fromRawJson(text);
      } on AppException catch (e) {
        if (e.code == 'invalid_api_key' || e.code == 'quota_exceeded') {
          rethrow;
        }
        lastError = e;
        _log.warning('Attempt $attempt failed: $e');
      } catch (e, st) {
        lastError = e;
        _log.warning('Attempt $attempt failed', e, st);
      }
      if (attempt < GeminiConfig.maxRetries) {
        await Future<void>.delayed(GeminiConfig.retryDelay * attempt);
      }
    }

    if (lastError is AppException) throw lastError;
    throw AppException.transcriptionFailed(lastError?.toString());
  }

  Future<String> _transcribeInline({
    required String apiKey,
    required String audioPath,
    required String mimeType,
    required String prompt,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.25, 'Uploading audio…');
    final bytes = await File(audioPath).readAsBytes();
    onProgress?.call(0.45, 'Generating subtitles…');

    final model = GenerativeModel(
      model: GeminiConfig.model,
      apiKey: apiKey,
    );

    try {
      final response = await model
          .generateContent([
            Content.multi([
              TextPart(prompt),
              DataPart(mimeType, bytes),
            ]),
          ])
          .timeout(GeminiConfig.requestTimeout);

      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw AppException.transcriptionFailed('Empty model response');
      }
      return text;
    } on GenerativeAIException catch (e) {
      throw _mapGenerativeError(e);
    } on SocketException {
      throw AppException.noInternet();
    }
  }

  Future<String> _transcribeViaFilesApi({
    required String apiKey,
    required String audioPath,
    required String mimeType,
    required String prompt,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.2, 'Uploading audio…');
    final uploaded = await _uploadFile(
      apiKey: apiKey,
      audioPath: audioPath,
      mimeType: mimeType,
    );
    onProgress?.call(0.55, 'Generating subtitles…');

    try {
      final uri = Uri.parse(
        '${GeminiConfig.generateContentUrl(GeminiConfig.model)}?key=$apiKey',
      );
      final body = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'file_data': {
                  'mime_type': mimeType,
                  'file_uri': uploaded['uri'],
                },
              },
            ],
          },
        ],
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(GeminiConfig.requestTimeout);

      if (response.statusCode >= 400) {
        throw AppException.fromGeminiStatus(
          response.statusCode,
          response.body,
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw AppException.transcriptionFailed('No candidates returned');
      }
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final text = parts
          ?.map((p) => p is Map ? p['text'] : null)
          .whereType<String>()
          .join('\n');
      if (text == null || text.trim().isEmpty) {
        throw AppException.transcriptionFailed('Empty model response');
      }
      return text;
    } on SocketException {
      throw AppException.noInternet();
    } finally {
      final name = uploaded['name']?.toString();
      if (name != null) {
        await _deleteFile(apiKey: apiKey, name: name);
      }
    }
  }

  /// Resumable upload for large audio without requiring a custom server.
  Future<Map<String, dynamic>> _uploadFile({
    required String apiKey,
    required String audioPath,
    required String mimeType,
  }) async {
    final file = File(audioPath);
    final length = await file.length();
    final displayName = p.basename(audioPath);

    final startUri = Uri.parse(
      '${GeminiConfig.filesUploadUrl()}?key=$apiKey',
    );
    final start = await _client.post(
      startUri,
      headers: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '$length',
        'X-Goog-Upload-Header-Content-Type': mimeType,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'file': {'display_name': displayName},
      }),
    );

    if (start.statusCode >= 400) {
      throw AppException.fromGeminiStatus(start.statusCode, start.body);
    }

    final uploadUrl = start.headers['x-goog-upload-url'] ??
        start.headers['X-Goog-Upload-URL'];
    if (uploadUrl == null) {
      throw AppException.transcriptionFailed('Missing upload URL');
    }

    // Stream file bytes for the upload body.
    final bytes = file.openRead();
    final request = http.StreamedRequest('POST', Uri.parse(uploadUrl));
    request.headers.addAll({
      'Content-Length': '$length',
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    });
    await bytes.forEach(request.sink.add);
    await request.sink.close();

    final streamed = await _client.send(request).timeout(
          GeminiConfig.requestTimeout,
        );
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw AppException.fromGeminiStatus(streamed.statusCode, body);
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final fileInfo = decoded['file'] as Map<String, dynamic>? ?? decoded;
    final name = fileInfo['name']?.toString();
    final uri = fileInfo['uri']?.toString();
    if (name == null || uri == null) {
      throw AppException.transcriptionFailed('Invalid Files API response');
    }

    // Wait until ACTIVE.
    for (var i = 0; i < 30; i++) {
      final status = await _getFile(apiKey: apiKey, name: name);
      final state = status['state']?.toString();
      if (state == 'ACTIVE') return status;
      if (state == 'FAILED') {
        throw AppException.transcriptionFailed('Audio upload processing failed');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return fileInfo;
  }

  Future<Map<String, dynamic>> _getFile({
    required String apiKey,
    required String name,
  }) async {
    final uri = Uri.parse('${GeminiConfig.filesUrl()}/$name?key=$apiKey');
    // name may already include "files/..."
    final normalized = name.startsWith('files/')
        ? Uri.parse('${GeminiConfig.baseUrl}/${GeminiConfig.apiVersion}/$name?key=$apiKey')
        : uri;
    final response = await _client.get(normalized);
    if (response.statusCode >= 400) {
      throw AppException.fromGeminiStatus(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _deleteFile({
    required String apiKey,
    required String name,
  }) async {
    try {
      final path = name.startsWith('files/') ? name : 'files/$name';
      final uri = Uri.parse(
        '${GeminiConfig.baseUrl}/${GeminiConfig.apiVersion}/$path?key=$apiKey',
      );
      await _client.delete(uri);
    } catch (e) {
      _log.fine('Failed to delete uploaded file: $e');
    }
  }

  AppException _mapGenerativeError(GenerativeAIException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('api key') || msg.contains('permission')) {
      return AppException.invalidApiKey();
    }
    if (msg.contains('quota') || msg.contains('rate')) {
      return AppException.quotaExceeded();
    }
    return AppException.transcriptionFailed(e.message);
  }

  String _mimeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.m4a' || '.aac' => 'audio/mp4',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.flac' => 'audio/flac',
      _ => 'audio/mp4',
    };
  }
}
