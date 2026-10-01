import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_language.dart';
import '../../models/export_quality.dart';
import '../../widgets/studio_widgets.dart';
import '../subtitle_styles/subtitle_preset_catalog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool? _apiOk;
  String? _apiMessage;
  String _presetId = 'clean';
  ExportQuality _quality = ExportQuality.balanced;
  String _sourceLang = 'auto';
  String _subtitleLang = 'ckb';
  bool _loaded = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = ref.read(secureStorageProvider);
    final key = await storage.getApiKey();
    final preset = await storage.getDefaultPreset();
    final quality = await storage.getDefaultExportQuality();
    final source = await storage.getSourceLanguage();
    final subtitle = await storage.getSubtitleLanguage();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _presetId = preset;
      _quality = quality;
      _sourceLang = source;
      _subtitleLang = subtitle;
      _loaded = true;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _saveKey() async {
    setState(() => _saving = true);
    await ref
        .read(secureStorageProvider)
        .saveApiKey(_apiKeyController.text.trim());
    ref.invalidate(apiKeyProvider);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved')),
      );
    }
  }

  Future<void> _testKey() async {
    setState(() {
      _apiOk = null;
      _apiMessage = 'Testing…';
    });
    try {
      final ok = await ref
          .read(geminiServiceProvider)
          .validateApiKey(_apiKeyController.text.trim());
      setState(() {
        _apiOk = ok;
        _apiMessage = ok ? 'API connected' : 'Invalid Gemini API key';
      });
      if (ok) await _saveKey();
    } catch (e) {
      setState(() {
        _apiOk = false;
        _apiMessage = e.toString();
      });
    }
  }

  Future<void> _savePrefs() async {
    final storage = ref.read(secureStorageProvider);
    await storage.setDefaultPreset(_presetId);
    await storage.setDefaultExportQuality(_quality);
    await storage.setSourceLanguage(_sourceLang);
    await storage.setSubtitleLanguage(_subtitleLang);
    ref.read(homeControllerProvider.notifier).setSourceLanguage(_sourceLang);
    ref.read(homeControllerProvider.notifier).setSubtitleLanguage(_subtitleLang);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Defaults saved')),
      );
    }
  }

  Future<void> _clearTemp() async {
    final count = await ref.read(tempFileServiceProvider).clearAllTempFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared $count temporary file(s)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('GEMINI API'),
                    const SizedBox(height: 6),
                    const Text(
                      'Key stays on this device only.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'Paste Gemini API key',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StudioButton(
                            label: 'Save',
                            busy: _saving,
                            onPressed: _saveKey,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StudioButton(
                            label: 'Test',
                            filled: false,
                            onPressed: _testKey,
                          ),
                        ),
                      ],
                    ),
                    if (_apiMessage != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            _apiOk == true
                                ? Icons.check_circle
                                : _apiOk == false
                                    ? Icons.error
                                    : Icons.hourglass_top,
                            color: _apiOk == true
                                ? AppColors.success
                                : _apiOk == false
                                    ? AppColors.danger
                                    : AppColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_apiMessage!)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('DEFAULTS'),
                    const SizedBox(height: 12),
                    const Text(
                      'Video spoken language',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('set-src-$_sourceLang'),
                      initialValue: _sourceLang,
                      items: [
                        for (final l in AppLanguage.sourceOptions)
                          DropdownMenuItem(value: l.code, child: Text(l.display)),
                      ],
                      onChanged: (v) =>
                          setState(() => _sourceLang = v ?? 'auto'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Subtitle language',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('set-sub-$_subtitleLang'),
                      initialValue: _subtitleLang,
                      items: [
                        for (final l in AppLanguage.subtitleOptions)
                          DropdownMenuItem(value: l.code, child: Text(l.display)),
                      ],
                      onChanged: (v) =>
                          setState(() => _subtitleLang = v ?? 'ckb'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Default preset',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('set-preset-$_presetId'),
                      initialValue: _presetId,
                      items: [
                        for (final p in SubtitlePresetCatalog.all)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) =>
                          setState(() => _presetId = v ?? 'clean'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Export quality',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final q in ExportQuality.values) ...[
                          if (q != ExportQuality.values.first)
                            const SizedBox(width: 8),
                          QualityChip(
                            label: q.label,
                            selected: _quality == q,
                            onTap: () => setState(() => _quality = q),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    StudioButton(label: 'Save Defaults', onPressed: _savePrefs),
                    const SizedBox(height: 10),
                    StudioButton(
                      label: 'Clear Temporary Files',
                      filled: false,
                      onPressed: _clearTemp,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${AppConfig.appName} · caption montage studio',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
