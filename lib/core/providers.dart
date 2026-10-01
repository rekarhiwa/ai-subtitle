import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/export/subtitle_export_service.dart';
import '../features/montage/feature_ops.dart';
import '../features/subtitle_editor/clip_ops.dart';
import '../features/subtitle_styles/subtitle_preset_catalog.dart';
import '../models/app_language.dart';
import '../models/audio_clip.dart';
import '../models/export_quality.dart';
import '../models/montage_project.dart';
import '../models/sticker_item.dart';
import '../models/subtitle_animation_config.dart';
import '../models/subtitle_segment.dart';
import '../models/subtitle_style.dart';
import '../models/video_clip.dart';
import '../models/video_metadata.dart';
import '../services/ffmpeg/ffmpeg_service.dart';
import '../services/fonts/font_service.dart';
import '../services/gemini/gemini_service.dart';
import '../services/storage/project_store.dart';
import '../services/storage/secure_storage_service.dart';
import '../services/temp/temp_file_service.dart';

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final projectStoreProvider = Provider<ProjectStore>(
  (ref) => ProjectStore(),
);

final tempFileServiceProvider = Provider<TempFileService>(
  (ref) => TempFileService(ref.watch(secureStorageProvider)),
);

final recentProjectsProvider =
    FutureProvider.autoDispose<List<MontageProject>>((ref) async {
  return ref.watch(projectStoreProvider).listRecent();
});

final ffmpegServiceProvider = Provider<FFmpegService>(
  (ref) => FFmpegService(),
);

final geminiServiceProvider = Provider<GeminiService>(
  (ref) => GeminiService(),
);

final fontServiceProvider = Provider<FontService>(
  (ref) => FontService(),
);

final subtitleExportServiceProvider = Provider<SubtitleExportService>(
  (ref) => SubtitleExportService(),
);

final apiKeyProvider = FutureProvider<String?>((ref) async {
  return ref.watch(secureStorageProvider).getApiKey();
});

enum ProcessingPhase {
  idle,
  extractingAudio,
  uploadingAudio,
  generatingSubtitles,
  preparingTimeline,
  exporting,
  done,
  error,
}

class HomeState {
  const HomeState({
    this.video,
    this.projectId,
    this.sourceLanguageCode = 'auto',
    this.subtitleLanguageCode = 'ckb',
    this.languageCode = 'ckb',
    this.languageLabel = 'Kurdish Sorani',
    this.phase = ProcessingPhase.idle,
    this.progress = 0,
    this.statusMessage = '',
    this.errorMessage,
    this.segments = const [],
  });

  final VideoMetadata? video;
  final String? projectId;
  /// Spoken language in the video (`auto` = detect).
  final String sourceLanguageCode;
  /// Desired subtitle language code.
  final String subtitleLanguageCode;
  final String languageCode;
  final String languageLabel;
  final ProcessingPhase phase;
  final double progress;
  final String statusMessage;
  final String? errorMessage;
  final List<SubtitleSegment> segments;

  bool get isBusy =>
      phase == ProcessingPhase.extractingAudio ||
      phase == ProcessingPhase.uploadingAudio ||
      phase == ProcessingPhase.generatingSubtitles ||
      phase == ProcessingPhase.preparingTimeline ||
      phase == ProcessingPhase.exporting;

  bool get isTranslateMode =>
      sourceLanguageCode != 'auto' &&
      sourceLanguageCode != subtitleLanguageCode;

  HomeState copyWith({
    VideoMetadata? video,
    String? projectId,
    String? sourceLanguageCode,
    String? subtitleLanguageCode,
    String? languageCode,
    String? languageLabel,
    ProcessingPhase? phase,
    double? progress,
    String? statusMessage,
    String? errorMessage,
    List<SubtitleSegment>? segments,
    bool clearError = false,
    bool clearVideo = false,
  }) {
    return HomeState(
      video: clearVideo ? null : (video ?? this.video),
      projectId: projectId ?? this.projectId,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      subtitleLanguageCode: subtitleLanguageCode ?? this.subtitleLanguageCode,
      languageCode: languageCode ?? this.languageCode,
      languageLabel: languageLabel ?? this.languageLabel,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      segments: segments ?? this.segments,
    );
  }
}

class HomeController extends Notifier<HomeState> {
  @override
  HomeState build() {
    Future.microtask(_loadLanguagePrefs);
    return const HomeState();
  }

  Future<void> _loadLanguagePrefs() async {
    final storage = ref.read(secureStorageProvider);
    final source = await storage.getSourceLanguage();
    final subtitle = await storage.getSubtitleLanguage();
    final subtitleLang = AppLanguage.byCode(
      subtitle,
      from: AppLanguage.subtitleOptions,
    );
    state = state.copyWith(
      sourceLanguageCode: source,
      subtitleLanguageCode: subtitle,
      languageCode: subtitle,
      languageLabel: subtitleLang.label,
    );
  }

  Future<void> setSourceLanguage(String code) async {
    state = state.copyWith(sourceLanguageCode: code);
    await ref.read(secureStorageProvider).setSourceLanguage(code);
  }

  Future<void> setSubtitleLanguage(String code) async {
    final lang = AppLanguage.byCode(code, from: AppLanguage.subtitleOptions);
    state = state.copyWith(
      subtitleLanguageCode: code,
      languageCode: code,
      languageLabel: lang.label,
    );
    await ref.read(secureStorageProvider).setSubtitleLanguage(code);
  }

  Future<void> selectVideo(String path) async {
    final ffmpeg = ref.read(ffmpegServiceProvider);
    final temp = ref.read(tempFileServiceProvider);
    final store = ref.read(projectStoreProvider);
    state = state.copyWith(
      phase: ProcessingPhase.idle,
      clearError: true,
      statusMessage: 'Reading video…',
    );
    final meta = await ffmpeg.getVideoMetadata(path);
    final thumbPath = await temp.createPath(
      'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    String? thumb;
    try {
      thumb = await ffmpeg.generateThumbnail(
        videoPath: path,
        outputPath: thumbPath,
      );
    } catch (_) {
      thumb = null;
    }
    final video = meta.copyWith(thumbnailPath: thumb);
    final project = await store.createFromVideo(video);
    ref.invalidate(recentProjectsProvider);
    state = state.copyWith(
      video: video,
      projectId: project.id,
      statusMessage: '',
      segments: const [],
    );
  }

  Future<void> generateSubtitles() async {
    final video = state.video;
    if (video == null) return;

    final storage = ref.read(secureStorageProvider);
    final apiKey = await storage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      state = state.copyWith(
        phase: ProcessingPhase.error,
        errorMessage:
            'Add your Gemini API key in Settings before generating subtitles.',
      );
      return;
    }

    final ffmpeg = ref.read(ffmpegServiceProvider);
    final gemini = ref.read(geminiServiceProvider);
    final temp = ref.read(tempFileServiceProvider);

    try {
      state = state.copyWith(
        phase: ProcessingPhase.extractingAudio,
        progress: 0.05,
        statusMessage: 'Extracting audio…',
        clearError: true,
      );

      final audioOut = await temp.createPath(
        'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      final audioPath = await ffmpeg.extractAudio(
        videoPath: video.path,
        outputPath: audioOut,
        onProgress: (p, msg) {
          state = state.copyWith(
            phase: ProcessingPhase.extractingAudio,
            progress: 0.05 + p * 0.25,
            statusMessage: msg,
          );
        },
      );
      temp.track(audioPath);

      state = state.copyWith(
        phase: ProcessingPhase.uploadingAudio,
        progress: 0.35,
        statusMessage: state.isTranslateMode
            ? 'AI translate → ${state.subtitleLanguageCode}…'
            : 'AI captions (${state.subtitleLanguageCode})…',
      );

      final result = await gemini.transcribeAudio(
        apiKey: apiKey,
        audioPath: audioPath,
        sourceLanguage: AppLanguage.byCode(
          state.sourceLanguageCode,
          from: AppLanguage.sourceOptions,
          fallback: AppLanguage.auto,
        ),
        subtitleLanguage: AppLanguage.byCode(
          state.subtitleLanguageCode,
          from: AppLanguage.subtitleOptions,
        ),
        mediaDuration: video.duration,
        onProgress: (p, msg) {
          final phase = msg.toLowerCase().contains('upload')
              ? ProcessingPhase.uploadingAudio
              : msg.toLowerCase().contains('preparing')
                  ? ProcessingPhase.preparingTimeline
                  : ProcessingPhase.generatingSubtitles;
          state = state.copyWith(
            phase: phase,
            progress: 0.35 + p * 0.6,
            statusMessage: msg,
          );
        },
      );

      state = state.copyWith(
        phase: ProcessingPhase.done,
        progress: 1,
        statusMessage: 'Subtitles ready',
        segments: result.segments,
      );

      final projectId = state.projectId;
      if (projectId != null) {
        final store = ref.read(projectStoreProvider);
        final existing = await store.load(projectId);
        if (existing != null) {
          await store.save(existing.copyWith(captions: result.segments));
          ref.invalidate(recentProjectsProvider);
        }
      }

      // Best-effort cleanup of extracted audio.
      await temp.delete(audioPath);
    } catch (e) {
      state = state.copyWith(
        phase: ProcessingPhase.error,
        errorMessage: e.toString(),
        statusMessage: '',
      );
    }
  }

  void setLanguage(String code, String label) {
    state = state.copyWith(
      languageCode: code,
      languageLabel: label,
      subtitleLanguageCode: code,
    );
  }

  void resetPhase() {
    state = state.copyWith(
      phase: ProcessingPhase.idle,
      progress: 0,
      statusMessage: '',
      clearError: true,
    );
  }

  Future<void> cancel() async {
    await ref.read(ffmpegServiceProvider).cancelProcessing();
    state = state.copyWith(
      phase: ProcessingPhase.idle,
      statusMessage: 'Cancelled',
      progress: 0,
    );
  }
}

final homeControllerProvider =
    NotifierProvider<HomeController, HomeState>(HomeController.new);

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.segments,
    required this.videoClips,
    required this.audioClips,
    required this.stickers,
    required this.style,
    required this.animation,
    required this.presetId,
    required this.muteOriginalAudio,
  });

  final List<SubtitleSegment> segments;
  final List<VideoClip> videoClips;
  final List<AudioClip> audioClips;
  final List<StickerItem> stickers;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  final String presetId;
  final bool muteOriginalAudio;
}

class EditorState {
  const EditorState({
    required this.video,
    required this.segments,
    this.projectId,
    this.videoClips = const [],
    this.audioClips = const [],
    this.stickers = const [],
    this.style = const SubtitleStyle(),
    this.animation = SubtitleAnimationConfig.fade,
    this.presetId = 'clean',
    this.exportQuality = ExportQuality.balanced,
    this.muteOriginalAudio = false,
    this.aspectRatio = '9:16',
    this.canvasColor = 0xFF000000,
    this.snapEnabled = true,
    this.duckingEnabled = false,
    this.watermarkText = '',
    this.proxyMode = false,
    this.hwAccel = false,
    this.brandKitId = '',
    this.textTracking = false,
    this.exportFps = 30,
    this.activeSegmentId,
    this.activeClipId,
    this.isExporting = false,
    this.exportProgress = 0,
    this.exportMessage = '',
    this.lastExportPath,
    this.errorMessage,
    this.canUndo = false,
    this.canRedo = false,
  });

  final VideoMetadata video;
  final String? projectId;
  final List<SubtitleSegment> segments;
  final List<VideoClip> videoClips;
  final List<AudioClip> audioClips;
  final List<StickerItem> stickers;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  final String presetId;
  final ExportQuality exportQuality;
  final bool muteOriginalAudio;
  final String aspectRatio;
  final int canvasColor;
  final bool snapEnabled;
  final bool duckingEnabled;
  final String watermarkText;
  final bool proxyMode;
  final bool hwAccel;
  final String brandKitId;
  final bool textTracking;
  final int exportFps;
  final String? activeSegmentId;
  final String? activeClipId;
  final bool isExporting;
  final double exportProgress;
  final String exportMessage;
  final String? lastExportPath;
  final String? errorMessage;
  final bool canUndo;
  final bool canRedo;

  Duration get timelineDuration {
    var maxMs = video.duration.inMilliseconds;
    for (final c in videoClips) {
      if (c.timelineEnd.inMilliseconds > maxMs) {
        maxMs = c.timelineEnd.inMilliseconds;
      }
    }
    return Duration(milliseconds: maxMs);
  }

  EditorState copyWith({
    VideoMetadata? video,
    String? projectId,
    List<SubtitleSegment>? segments,
    List<VideoClip>? videoClips,
    List<AudioClip>? audioClips,
    List<StickerItem>? stickers,
    SubtitleStyle? style,
    SubtitleAnimationConfig? animation,
    String? presetId,
    ExportQuality? exportQuality,
    bool? muteOriginalAudio,
    String? aspectRatio,
    int? canvasColor,
    bool? snapEnabled,
    bool? duckingEnabled,
    String? watermarkText,
    bool? proxyMode,
    bool? hwAccel,
    String? brandKitId,
    bool? textTracking,
    int? exportFps,
    String? activeSegmentId,
    String? activeClipId,
    bool? isExporting,
    double? exportProgress,
    String? exportMessage,
    String? lastExportPath,
    String? errorMessage,
    bool? canUndo,
    bool? canRedo,
    bool clearActive = false,
    bool clearClip = false,
    bool clearError = false,
  }) {
    return EditorState(
      video: video ?? this.video,
      projectId: projectId ?? this.projectId,
      segments: segments ?? this.segments,
      videoClips: videoClips ?? this.videoClips,
      audioClips: audioClips ?? this.audioClips,
      stickers: stickers ?? this.stickers,
      style: style ?? this.style,
      animation: animation ?? this.animation,
      presetId: presetId ?? this.presetId,
      exportQuality: exportQuality ?? this.exportQuality,
      muteOriginalAudio: muteOriginalAudio ?? this.muteOriginalAudio,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      canvasColor: canvasColor ?? this.canvasColor,
      snapEnabled: snapEnabled ?? this.snapEnabled,
      duckingEnabled: duckingEnabled ?? this.duckingEnabled,
      watermarkText: watermarkText ?? this.watermarkText,
      proxyMode: proxyMode ?? this.proxyMode,
      hwAccel: hwAccel ?? this.hwAccel,
      brandKitId: brandKitId ?? this.brandKitId,
      textTracking: textTracking ?? this.textTracking,
      exportFps: exportFps ?? this.exportFps,
      activeSegmentId:
          clearActive ? null : (activeSegmentId ?? this.activeSegmentId),
      activeClipId: clearClip ? null : (activeClipId ?? this.activeClipId),
      isExporting: isExporting ?? this.isExporting,
      exportProgress: exportProgress ?? this.exportProgress,
      exportMessage: exportMessage ?? this.exportMessage,
      lastExportPath: lastExportPath ?? this.lastExportPath,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
    );
  }
}

class EditorController extends Notifier<EditorState?> {
  final List<_EditorSnapshot> _undo = [];
  final List<_EditorSnapshot> _redo = [];
  Timer? _autosave;

  @override
  EditorState? build() {
    ref.onDispose(() => _autosave?.cancel());
    return null;
  }

  _EditorSnapshot _snap(EditorState s) => _EditorSnapshot(
        segments: s.segments.map((e) => e.copyWith()).toList(),
        videoClips: List.of(s.videoClips),
        audioClips: List.of(s.audioClips),
        stickers: List.of(s.stickers),
        style: s.style,
        animation: s.animation,
        presetId: s.presetId,
        muteOriginalAudio: s.muteOriginalAudio,
      );

  void _pushUndo() {
    final current = state;
    if (current == null) return;
    _undo.add(_snap(current));
    if (_undo.length > 20) _undo.removeAt(0);
    _redo.clear();
    state = current.copyWith(canUndo: _undo.isNotEmpty, canRedo: false);
  }

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 2), () => persist());
  }

  Future<void> persist() async {
    final current = state;
    if (current?.projectId == null) return;
    final store = ref.read(projectStoreProvider);
    final existing = await store.load(current!.projectId!);
    if (existing == null) return;
    await store.save(
      existing.copyWith(
        captions: current.segments,
        videoClips: current.videoClips,
        audioClips: current.audioClips,
        stickers: current.stickers,
        style: current.style,
        animation: current.animation,
        presetId: current.presetId,
        exportQuality: current.exportQuality,
        muteOriginalAudio: current.muteOriginalAudio,
        aspectRatio: current.aspectRatio,
        canvasColor: current.canvasColor,
        snapEnabled: current.snapEnabled,
        primaryVideo: current.video,
      ),
    );
    ref.invalidate(recentProjectsProvider);
  }

  Future<void> open({
    required VideoMetadata video,
    required List<SubtitleSegment> segments,
    String? projectId,
    List<VideoClip>? videoClips,
    List<AudioClip>? audioClips,
    List<StickerItem>? stickers,
    SubtitleStyle? style,
    SubtitleAnimationConfig? animation,
    String? presetId,
    ExportQuality? exportQuality,
    bool muteOriginalAudio = false,
    String aspectRatio = '9:16',
    int canvasColor = 0xFF000000,
    bool snapEnabled = true,
  }) async {
    final storage = ref.read(secureStorageProvider);
    final resolvedPresetId = presetId ?? await storage.getDefaultPreset();
    final quality = exportQuality ?? await storage.getDefaultExportQuality();
    final preset = SubtitlePresetCatalog.byId(resolvedPresetId);
    _undo.clear();
    _redo.clear();
    final clips = videoClips ??
        [
          VideoClip.create(
            sourcePath: video.path,
            sourceDuration: video.duration,
            timelineStart: Duration.zero,
            thumbnailPath: video.thumbnailPath,
            fileName: video.fileName,
          ),
        ];
    state = EditorState(
      video: video,
      projectId: projectId,
      segments: segments,
      videoClips: clips,
      audioClips: audioClips ?? const [],
      stickers: stickers ?? const [],
      style: style ?? preset.style,
      animation: animation ?? SubtitleAnimationConfig.fade,
      presetId: resolvedPresetId,
      exportQuality: quality,
      muteOriginalAudio: muteOriginalAudio,
      aspectRatio: aspectRatio,
      canvasColor: canvasColor,
      snapEnabled: snapEnabled,
    );
  }

  Future<void> openProject(MontageProject project) async {
    await open(
      video: project.primaryVideo,
      segments: project.captions,
      projectId: project.id,
      videoClips: project.videoClips,
      audioClips: project.audioClips,
      stickers: project.stickers,
      style: project.style,
      animation: project.animation,
      presetId: project.presetId,
      exportQuality: project.exportQuality,
      muteOriginalAudio: project.muteOriginalAudio,
      aspectRatio: project.aspectRatio,
      canvasColor: project.canvasColor,
      snapEnabled: project.snapEnabled,
    );
  }

  void undo() {
    final current = state;
    if (current == null || _undo.isEmpty) return;
    _redo.add(_snap(current));
    final prev = _undo.removeLast();
    state = current.copyWith(
      segments: prev.segments,
      videoClips: prev.videoClips,
      audioClips: prev.audioClips,
      stickers: prev.stickers,
      style: prev.style,
      animation: prev.animation,
      presetId: prev.presetId,
      muteOriginalAudio: prev.muteOriginalAudio,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    _scheduleAutosave();
  }

  void redo() {
    final current = state;
    if (current == null || _redo.isEmpty) return;
    _undo.add(_snap(current));
    final next = _redo.removeLast();
    state = current.copyWith(
      segments: next.segments,
      videoClips: next.videoClips,
      audioClips: next.audioClips,
      stickers: next.stickers,
      style: next.style,
      animation: next.animation,
      presetId: next.presetId,
      muteOriginalAudio: next.muteOriginalAudio,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    _scheduleAutosave();
  }

  void setSegments(List<SubtitleSegment> segments) {
    _pushUndo();
    state = state?.copyWith(
      segments: segments,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void updateSegment(SubtitleSegment segment) {
    final current = state;
    if (current == null) return;
    _pushUndo();
    final next =
        current.segments.map((s) => s.id == segment.id ? segment : s).toList();
    state = current.copyWith(
      segments: next,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setVideoClips(List<VideoClip> clips) {
    _pushUndo();
    state = state?.copyWith(
      videoClips: clips,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void addVideoClip(VideoClip clip) {
    final current = state;
    if (current == null) return;
    _pushUndo();
    state = current.copyWith(
      videoClips: ClipOps.reflow([...current.videoClips, clip]),
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setAudioClips(List<AudioClip> clips) {
    _pushUndo();
    state = state?.copyWith(
      audioClips: clips,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void addAudioClip(AudioClip clip) {
    final current = state;
    if (current == null) return;
    _pushUndo();
    state = current.copyWith(
      audioClips: [...current.audioClips, clip],
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setStickers(List<StickerItem> stickers) {
    _pushUndo();
    state = state?.copyWith(
      stickers: stickers,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void addSticker(StickerItem sticker) {
    final current = state;
    if (current == null) return;
    _pushUndo();
    state = current.copyWith(
      stickers: [...current.stickers, sticker],
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setMuteOriginalAudio(bool mute) {
    _pushUndo();
    state = state?.copyWith(
      muteOriginalAudio: mute,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setAspectRatio(String ratio) {
    _pushUndo();
    state = state?.copyWith(
      aspectRatio: ratio,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setCanvasColor(int color) {
    _pushUndo();
    state = state?.copyWith(
      canvasColor: color,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setSnapEnabled(bool enabled) {
    state = state?.copyWith(snapEnabled: enabled);
    _scheduleAutosave();
  }

  void setDuckingEnabled(bool enabled) {
    final current = state;
    if (current == null) return;
    _pushUndo();
    final clips = FeatureOps.applyDucking(
      current.audioClips,
      enabled: enabled,
    );
    state = current.copyWith(
      duckingEnabled: enabled,
      audioClips: clips,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setWatermarkText(String text) {
    _pushUndo();
    state = state?.copyWith(
      watermarkText: text,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setProxyMode(bool enabled) {
    state = state?.copyWith(proxyMode: enabled);
  }

  void setHwAccel(bool enabled) {
    state = state?.copyWith(hwAccel: enabled);
  }

  void setExportFps(int fps) {
    state = state?.copyWith(exportFps: fps.clamp(24, 60));
  }

  void setTextTracking(bool enabled) {
    state = state?.copyWith(textTracking: enabled);
  }

  void applyBrandKit(String kitId) {
    final kit = FeatureOps.brandKits[kitId];
    if (kit == null || state == null) return;
    _pushUndo();
    state = state!.copyWith(
      brandKitId: kitId,
      style: FeatureOps.applyBrandKit(state!.style, kit),
      watermarkText: state!.watermarkText.isEmpty ? kit.name : state!.watermarkText,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void normalizeAudioVolumes() {
    final current = state;
    if (current == null) return;
    _pushUndo();
    state = current.copyWith(
      audioClips: FeatureOps.normalizeVolumes(current.audioClips),
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void updateActiveClip(VideoClip Function(VideoClip) fn) {
    final current = state;
    if (current == null || current.activeClipId == null) return;
    _pushUndo();
    state = current.copyWith(
      videoClips: ClipOps.update(current.videoClips, current.activeClipId!, fn),
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setActiveSegment(String? id) {
    state = state?.copyWith(activeSegmentId: id, clearActive: id == null);
  }

  void setActiveClip(String? id) {
    state = state?.copyWith(activeClipId: id, clearClip: id == null);
  }

  void applyPreset(String id) {
    _pushUndo();
    final preset = SubtitlePresetCatalog.byId(id);
    state = state?.copyWith(
      presetId: id,
      style: preset.style,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void updateStyle(SubtitleStyle style) {
    _pushUndo();
    state = state?.copyWith(
      style: style,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setAnimation(SubtitleAnimationConfig config) {
    _pushUndo();
    state = state?.copyWith(
      animation: config,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
    );
    _scheduleAutosave();
  }

  void setExportQuality(ExportQuality quality) {
    state = state?.copyWith(exportQuality: quality);
    _scheduleAutosave();
  }

  /// CapCut-style: run AI captions inside the open editor.
  Future<void> generateCaptions({
    String sourceLanguageCode = 'auto',
    String subtitleLanguageCode = 'ckb',
  }) async {
    final current = state;
    if (current == null) return;
    final storage = ref.read(secureStorageProvider);
    final apiKey = await storage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      state = current.copyWith(
        errorMessage:
            'کلیدی Gemini لە Settings زیاد بکە پێش Auto Captions.',
        clearError: false,
      );
      throw Exception('missing_api_key');
    }

    final ffmpeg = ref.read(ffmpegServiceProvider);
    final gemini = ref.read(geminiServiceProvider);
    final temp = ref.read(tempFileServiceProvider);

    try {
      setExporting(
        isExporting: true,
        progress: 0.05,
        message: 'دەرهێنانی دەنگ…',
        clearError: true,
      );
      final audioOut = await temp.createPath(
        'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      final audioPath = await ffmpeg.extractAudio(
        videoPath: current.video.path,
        outputPath: audioOut,
        onProgress: (p, msg) {
          setExporting(
            isExporting: true,
            progress: 0.05 + p * 0.25,
            message: msg,
          );
        },
      );
      temp.track(audioPath);

      setExporting(
        isExporting: true,
        progress: 0.35,
        message: 'AI ژێرنووس…',
      );

      final result = await gemini.transcribeAudio(
        apiKey: apiKey,
        audioPath: audioPath,
        sourceLanguage: AppLanguage.byCode(
          sourceLanguageCode,
          from: AppLanguage.sourceOptions,
          fallback: AppLanguage.auto,
        ),
        subtitleLanguage: AppLanguage.byCode(
          subtitleLanguageCode,
          from: AppLanguage.subtitleOptions,
        ),
        mediaDuration: current.video.duration,
        onProgress: (p, msg) {
          setExporting(
            isExporting: true,
            progress: 0.35 + p * 0.6,
            message: msg,
          );
        },
      );

      setSegments(result.segments);
      setExporting(
        isExporting: false,
        progress: 1,
        message: 'ژێرنووس ئامادەیە',
      );
      await temp.delete(audioPath);
    } catch (e) {
      setExporting(
        isExporting: false,
        errorMessage: e.toString(),
        message: '',
      );
      rethrow;
    }
  }

  void setExporting({
    required bool isExporting,
    double? progress,
    String? message,
    String? lastExportPath,
    String? errorMessage,
    bool clearError = false,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      isExporting: isExporting,
      exportProgress: progress,
      exportMessage: message,
      lastExportPath: lastExportPath,
      errorMessage: errorMessage,
      clearError: clearError,
    );
  }
}

final editorControllerProvider =
    NotifierProvider<EditorController, EditorState?>(EditorController.new);
