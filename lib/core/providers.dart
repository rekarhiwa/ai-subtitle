import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/export/subtitle_export_service.dart';
import '../features/subtitle_styles/subtitle_preset_catalog.dart';
import '../models/export_quality.dart';
import '../models/subtitle_animation_config.dart';
import '../models/subtitle_segment.dart';
import '../models/subtitle_style.dart';
import '../models/video_metadata.dart';
import '../services/ffmpeg/ffmpeg_service.dart';
import '../services/fonts/font_service.dart';
import '../services/gemini/gemini_service.dart';
import '../services/storage/secure_storage_service.dart';
import '../services/temp/temp_file_service.dart';

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final tempFileServiceProvider = Provider<TempFileService>(
  (ref) => TempFileService(ref.watch(secureStorageProvider)),
);

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
    this.languageCode = 'ckb',
    this.languageLabel = 'Kurdish Sorani',
    this.phase = ProcessingPhase.idle,
    this.progress = 0,
    this.statusMessage = '',
    this.errorMessage,
    this.segments = const [],
  });

  final VideoMetadata? video;
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

  HomeState copyWith({
    VideoMetadata? video,
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
  HomeState build() => const HomeState();

  Future<void> selectVideo(String path) async {
    final ffmpeg = ref.read(ffmpegServiceProvider);
    final temp = ref.read(tempFileServiceProvider);
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
    state = state.copyWith(
      video: meta.copyWith(thumbnailPath: thumb),
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
        statusMessage: 'Uploading audio…',
      );

      final result = await gemini.transcribeAudio(
        apiKey: apiKey,
        audioPath: audioPath,
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
    state = state.copyWith(languageCode: code, languageLabel: label);
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

class EditorState {
  const EditorState({
    required this.video,
    required this.segments,
    this.style = const SubtitleStyle(),
    this.animation = SubtitleAnimationConfig.fade,
    this.presetId = 'clean',
    this.exportQuality = ExportQuality.balanced,
    this.activeSegmentId,
    this.isExporting = false,
    this.exportProgress = 0,
    this.exportMessage = '',
    this.lastExportPath,
    this.errorMessage,
  });

  final VideoMetadata video;
  final List<SubtitleSegment> segments;
  final SubtitleStyle style;
  final SubtitleAnimationConfig animation;
  final String presetId;
  final ExportQuality exportQuality;
  final String? activeSegmentId;
  final bool isExporting;
  final double exportProgress;
  final String exportMessage;
  final String? lastExportPath;
  final String? errorMessage;

  EditorState copyWith({
    VideoMetadata? video,
    List<SubtitleSegment>? segments,
    SubtitleStyle? style,
    SubtitleAnimationConfig? animation,
    String? presetId,
    ExportQuality? exportQuality,
    String? activeSegmentId,
    bool? isExporting,
    double? exportProgress,
    String? exportMessage,
    String? lastExportPath,
    String? errorMessage,
    bool clearActive = false,
    bool clearError = false,
  }) {
    return EditorState(
      video: video ?? this.video,
      segments: segments ?? this.segments,
      style: style ?? this.style,
      animation: animation ?? this.animation,
      presetId: presetId ?? this.presetId,
      exportQuality: exportQuality ?? this.exportQuality,
      activeSegmentId:
          clearActive ? null : (activeSegmentId ?? this.activeSegmentId),
      isExporting: isExporting ?? this.isExporting,
      exportProgress: exportProgress ?? this.exportProgress,
      exportMessage: exportMessage ?? this.exportMessage,
      lastExportPath: lastExportPath ?? this.lastExportPath,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class EditorController extends Notifier<EditorState?> {
  @override
  EditorState? build() => null;

  Future<void> open({
    required VideoMetadata video,
    required List<SubtitleSegment> segments,
  }) async {
    final storage = ref.read(secureStorageProvider);
    final presetId = await storage.getDefaultPreset();
    final quality = await storage.getDefaultExportQuality();
    final preset = SubtitlePresetCatalog.byId(presetId);
    state = EditorState(
      video: video,
      segments: segments,
      style: preset.style,
      presetId: preset.id,
      exportQuality: quality,
    );
  }

  void setSegments(List<SubtitleSegment> segments) {
    state = state?.copyWith(segments: segments);
  }

  void updateSegment(SubtitleSegment segment) {
    final current = state;
    if (current == null) return;
    final next = current.segments
        .map((s) => s.id == segment.id ? segment : s)
        .toList();
    state = current.copyWith(segments: next);
  }

  void setActiveSegment(String? id) {
    state = state?.copyWith(activeSegmentId: id, clearActive: id == null);
  }

  void applyPreset(String id) {
    final preset = SubtitlePresetCatalog.byId(id);
    state = state?.copyWith(presetId: id, style: preset.style);
  }

  void updateStyle(SubtitleStyle style) {
    state = state?.copyWith(style: style);
  }

  void setAnimation(SubtitleAnimationConfig config) {
    state = state?.copyWith(animation: config);
  }

  void setExportQuality(ExportQuality quality) {
    state = state?.copyWith(exportQuality: quality);
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
