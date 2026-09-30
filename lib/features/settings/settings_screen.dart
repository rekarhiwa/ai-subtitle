import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
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
  final _tempDirController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool? _apiOk;
  String? _apiMessage;
  String _presetId = 'clean';
  ExportQuality _quality = ExportQuality.balanced;
  bool _loaded = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _tempDirController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = ref.read(secureStorageProvider);
    final key = await storage.getApiKey();
    final preset = await storage.getDefaultPreset();
    final quality = await storage.getDefaultExportQuality();
    final temp = await storage.getTempDirectoryOverride();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _presetId = preset;
      _quality = quality;
      _tempDirController.text = temp ?? '';
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
    await ref.read(secureStorageProvider).saveApiKey(_apiKeyController.text.trim());
    ref.invalidate(apiKeyProvider);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved securely')),
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
    await storage.setTempDirectoryOverride(
      _tempDirController.text.trim().isEmpty
          ? null
          : _tempDirController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
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
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('GEMINI API'),
                    const SizedBox(height: 8),
                    const Text(
                      'Key stays on this device. Never hardcoded.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'Paste Gemini API key',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StudioButton(
                            label: 'Save Key',
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
                    const Text('Language'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Kurdish Sorani',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Preset'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _presetId,
                      items: [
                        for (final p in SubtitlePresetCatalog.all)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) => setState(() => _presetId = v ?? 'clean'),
                    ),
                    const SizedBox(height: 14),
                    const Text('Export quality'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ExportQuality>(
                      initialValue: _quality,
                      items: [
                        for (final q in ExportQuality.values)
                          DropdownMenuItem(value: q, child: Text(q.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => _quality = v ?? ExportQuality.balanced),
                    ),
                    const SizedBox(height: 14),
                    const Text('Temp directory override'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tempDirController,
                      decoration: const InputDecoration(
                        hintText: 'Leave empty for app temp folder',
                      ),
                    ),
                    const SizedBox(height: 16),
                    StudioButton(label: 'Save Settings', onPressed: _savePrefs),
                    const SizedBox(height: 10),
                    StudioButton(
                      label: 'Clear Temporary Files',
                      filled: false,
                      onPressed: _clearTemp,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
