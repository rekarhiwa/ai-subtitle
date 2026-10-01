import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../models/export_quality.dart';

class SecureStorageService {
  SecureStorageService({
    FlutterSecureStorage? secureStorage,
    this._prefs,
  }) : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  static const _apiKeyKey = 'gemini_api_key';
  static const _languageKey = 'default_language';
  static const _sourceLanguageKey = 'source_language';
  static const _subtitleLanguageKey = 'subtitle_language';
  static const _presetKey = 'default_preset';
  static const _qualityKey = 'default_export_quality';
  static const _tempDirKey = 'temp_files_directory';

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveApiKey(String key) async {
    await _secure.write(key: _apiKeyKey, value: key.trim());
  }

  Future<String?> getApiKey() => _secure.read(key: _apiKeyKey);

  Future<void> clearApiKey() => _secure.delete(key: _apiKeyKey);

  Future<void> setDefaultLanguage(String code) async {
    final prefs = await _getPrefs();
    await prefs.setString(_languageKey, code);
  }

  Future<String> getDefaultLanguage() async {
    final prefs = await _getPrefs();
    return prefs.getString(_languageKey) ?? AppConfig.defaultLanguageCode;
  }

  Future<void> setSourceLanguage(String code) async {
    final prefs = await _getPrefs();
    await prefs.setString(_sourceLanguageKey, code);
  }

  Future<String> getSourceLanguage() async {
    final prefs = await _getPrefs();
    return prefs.getString(_sourceLanguageKey) ?? 'auto';
  }

  Future<void> setSubtitleLanguage(String code) async {
    final prefs = await _getPrefs();
    await prefs.setString(_subtitleLanguageKey, code);
    await prefs.setString(_languageKey, code);
  }

  Future<String> getSubtitleLanguage() async {
    final prefs = await _getPrefs();
    return prefs.getString(_subtitleLanguageKey) ??
        prefs.getString(_languageKey) ??
        AppConfig.defaultLanguageCode;
  }

  Future<void> setDefaultPreset(String id) async {
    final prefs = await _getPrefs();
    await prefs.setString(_presetKey, id);
  }

  Future<String> getDefaultPreset() async {
    final prefs = await _getPrefs();
    return prefs.getString(_presetKey) ?? 'clean';
  }

  Future<void> setDefaultExportQuality(ExportQuality quality) async {
    final prefs = await _getPrefs();
    await prefs.setString(_qualityKey, quality.name);
  }

  Future<ExportQuality> getDefaultExportQuality() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_qualityKey);
    return ExportQuality.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ExportQuality.balanced,
    );
  }

  Future<void> setTempDirectoryOverride(String? path) async {
    final prefs = await _getPrefs();
    if (path == null || path.isEmpty) {
      await prefs.remove(_tempDirKey);
    } else {
      await prefs.setString(_tempDirKey, path);
    }
  }

  Future<String?> getTempDirectoryOverride() async {
    final prefs = await _getPrefs();
    return prefs.getString(_tempDirKey);
  }
}
