import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/timestamp_utils.dart';
import '../../models/export_quality.dart';
import '../../models/sticker_item.dart';
import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_segment.dart';
import '../../models/subtitle_style.dart';
import '../../models/video_clip.dart';
import '../../services/fonts/font_service.dart';
import '../../widgets/studio_widgets.dart';
import '../montage/ai_studio_panel.dart';
import '../montage/feature_browser.dart';
import '../montage/feature_ops.dart';
import '../montage/media_library.dart';
import '../subtitle_styles/subtitle_preset_catalog.dart';
import 'clip_ops.dart';
import 'capcut_widgets.dart';
import 'subtitle_ops.dart';

enum EditorTab { tools, edit, text, style, animation, audio, stickers, ai, export }

class EditorBottomDock extends StatelessWidget {
  const EditorBottomDock({
    super.key,
    required this.tab,
    required this.onTab,
  });

  final EditorTab tab;
  final ValueChanged<EditorTab> onTab;

  static const _items = <(EditorTab, IconData, String)>[
    (EditorTab.edit, Icons.content_cut_rounded, 'Edit'),
    (EditorTab.audio, Icons.music_note_rounded, 'Audio'),
    (EditorTab.text, Icons.text_fields_rounded, 'Text'),
    (EditorTab.style, Icons.filter_vintage_outlined, 'Filters'),
    (EditorTab.animation, Icons.auto_awesome, 'Effects'),
    (EditorTab.stickers, Icons.sticky_note_2_outlined, 'Overlay'),
    (EditorTab.ai, Icons.closed_caption_rounded, 'Captions'),
    (EditorTab.tools, Icons.grid_view_rounded, 'Tools'),
    (EditorTab.export, Icons.ios_share_rounded, 'Export'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: const Color(0xFF0A0A0A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final (t, icon, label) = _items[i];
          final selected = tab == t;
          return SizedBox(
            width: 64,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTab(t);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class EditorToolPanel extends ConsumerWidget {
  const EditorToolPanel({
    super.key,
    required this.tab,
    required this.editor,
    required this.position,
    required this.onSeek,
    required this.onExportSrt,
    required this.onExportAss,
    required this.onExportMp4,
    this.asSidePanel = false,
    this.onOpenTab,
    this.onImportMedia,
    this.onImportSrt,
    this.onExtractAudio,
    this.onBackup,
    this.onAddPreset,
    this.onExportGif,
    this.onBatchExport,
    this.onExportProjectJson,
    this.onImportProjectJson,
  });

  final EditorTab tab;
  final EditorState editor;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onExportSrt;
  final VoidCallback onExportAss;
  final VoidCallback onExportMp4;
  final bool asSidePanel;
  final ValueChanged<EditorTab>? onOpenTab;
  final VoidCallback? onImportMedia;
  final VoidCallback? onImportSrt;
  final VoidCallback? onExtractAudio;
  final VoidCallback? onBackup;
  final Future<void> Function(MediaPreset preset)? onAddPreset;
  final VoidCallback? onExportGif;
  final VoidCallback? onBatchExport;
  final VoidCallback? onExportProjectJson;
  final VoidCallback? onImportProjectJson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorControllerProvider.notifier);
    final fonts = ref.watch(fontServiceProvider).availableFonts;
    final activeId = editor.activeSegmentId;
    SubtitleSegment? active;
    for (final s in editor.segments) {
      if (s.id == activeId) {
        active = s;
        break;
      }
    }
    active ??= SubtitleOps.activeAt(editor.segments, position);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: asSidePanel
              ? const BorderSide(color: AppColors.border)
              : BorderSide.none,
          top: asSidePanel
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: CapCutSheetChrome(
        title: switch (tab) {
          EditorTab.tools => 'Tools',
          EditorTab.edit => 'Edit',
          EditorTab.text => 'Text',
          EditorTab.style => 'Filters',
          EditorTab.animation => 'Effects',
          EditorTab.audio => 'Audio',
          EditorTab.stickers => 'Overlay',
          EditorTab.ai => 'Captions',
          EditorTab.export => 'Export',
        },
        onClose: asSidePanel ? null : () => onOpenTab?.call(tab),
        child: switch (tab) {
        EditorTab.tools => FeatureBrowserPanel(
            editor: editor,
            position: position,
            onOpenTab: onOpenTab ?? (_) {},
            onImportMedia: onImportMedia,
            onImportSrt: onImportSrt,
            onExtractAudio: onExtractAudio,
            onBackup: onBackup,
          ),
        EditorTab.edit => _EditClipPanel(editor: editor, position: position),
        EditorTab.text => CaptionTextPanel(
            segments: editor.segments,
            activeId: active?.id ?? editor.activeSegmentId,
            mediaDuration: editor.timelineDuration,
            onTap: (s) {
              notifier.setActiveSegment(s.id);
              onSeek(s.start);
            },
            onChanged: notifier.updateSegment,
            onDelete: (id) =>
                notifier.setSegments(SubtitleOps.delete(editor.segments, id)),
            onSplit: (id) =>
                notifier.setSegments(SubtitleOps.split(editor.segments, id)),
            onMergeNext: (id) {
              final sorted = SubtitleOps.sorted(editor.segments);
              final i = sorted.indexWhere((s) => s.id == id);
              if (i < 0 || i >= sorted.length - 1) return;
              notifier.setSegments(
                SubtitleOps.merge(sorted, sorted[i].id, sorted[i + 1].id),
              );
            },
            onAdd: () {
              notifier.setSegments(
                SubtitleOps.add(
                  editor.segments,
                  start: position,
                  end: position + const Duration(seconds: 2),
                  text: 'نووسینی نوێ',
                ),
              );
            },
            onRemoveFillers: () => notifier.setSegments(
              SubtitleOps.removeFillers(editor.segments),
            ),
            onSplitSentences: () => notifier.setSegments(
              SubtitleOps.splitBySentences(editor.segments),
            ),
          ),
        EditorTab.style => _StyleStudio(
            editor: editor,
            fonts: fonts,
            onPreset: notifier.applyPreset,
            onStyle: notifier.updateStyle,
          ),
        EditorTab.animation => _EffectsGrid(
            selected: editor.animation.type,
            onSelect: (type) {
              final config = switch (type) {
                SubtitleAnimationType.none => SubtitleAnimationConfig.none,
                SubtitleAnimationType.fade => SubtitleAnimationConfig.fade,
                SubtitleAnimationType.pop => SubtitleAnimationConfig.pop,
                SubtitleAnimationType.slideUp =>
                  SubtitleAnimationConfig.slideUp,
                SubtitleAnimationType.slideLeft =>
                  SubtitleAnimationConfig.slideLeft,
                SubtitleAnimationType.slideRight =>
                  SubtitleAnimationConfig.slideRight,
                SubtitleAnimationType.wordByWord =>
                  const SubtitleAnimationConfig(
                    type: SubtitleAnimationType.wordByWord,
                    duration: Duration(milliseconds: 900),
                    opacityFrom: 0,
                    scaleFrom: 1,
                  ),
              };
              notifier.setAnimation(config);
            },
          ),
        EditorTab.audio => _AudioPanel(
            editor: editor,
            onAddPreset: onAddPreset,
          ),
        EditorTab.stickers => _StickersPanel(
            editor: editor,
            position: position,
          ),
        EditorTab.ai => AiStudioPanel(position: position),
        EditorTab.export => _ExportPanel(
            quality: editor.exportQuality,
            exporting: editor.isExporting,
            progress: editor.exportProgress,
            message: editor.exportMessage,
            onQuality: notifier.setExportQuality,
            onExportMp4: onExportMp4,
            onExportSrt: onExportSrt,
            onExportAss: onExportAss,
            onExportGif: onExportGif,
            onBatchExport: onBatchExport,
            onExportProjectJson: onExportProjectJson,
            onImportProjectJson: onImportProjectJson,
          ),
      },
      ),
    );
  }
}

class _EditClipPanel extends ConsumerStatefulWidget {
  const _EditClipPanel({required this.editor, required this.position});

  final EditorState editor;
  final Duration position;

  @override
  ConsumerState<_EditClipPanel> createState() => _EditClipPanelState();
}

enum _EditTool { none, speed, volume, opacity, crop, rotate, transition }

class _EditClipPanelState extends ConsumerState<_EditClipPanel> {
  _EditTool _tool = _EditTool.none;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final position = widget.position;
    final notifier = ref.read(editorControllerProvider.notifier);
    final activeId = editor.activeClipId;
    VideoClip? active;
    for (final c in editor.videoClips) {
      if (c.id == activeId) {
        active = c;
        break;
      }
    }
    final atPos = active ?? ClipOps.atPosition(editor.videoClips, position);

    void patch(VideoClip Function(VideoClip) fn) {
      if (atPos == null) return;
      notifier.setActiveClip(atPos.id);
      notifier.setVideoClips(
        ClipOps.update(editor.videoClips, atPos.id, fn),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              CapCutToolIcon(
                icon: Icons.call_split_rounded,
                label: 'Split',
                enabled: atPos != null,
                onTap: atPos == null
                    ? null
                    : () => notifier.setVideoClips(
                          ClipOps.split(editor.videoClips, atPos.id, position),
                        ),
              ),
              CapCutToolIcon(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                danger: true,
                enabled: atPos != null && editor.videoClips.length > 1,
                onTap: atPos == null
                    ? null
                    : () => notifier.setVideoClips(
                          ClipOps.rippleDelete(editor.videoClips, atPos.id),
                        ),
              ),
              CapCutToolIcon(
                icon: Icons.speed_rounded,
                label: 'Speed',
                selected: _tool == _EditTool.speed,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.speed),
              ),
              CapCutToolIcon(
                icon: Icons.volume_up_rounded,
                label: 'Volume',
                selected: _tool == _EditTool.volume,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.volume),
              ),
              CapCutToolIcon(
                icon: Icons.opacity_rounded,
                label: 'Opacity',
                selected: _tool == _EditTool.opacity,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.opacity),
              ),
              CapCutToolIcon(
                icon: Icons.crop_rounded,
                label: 'Crop',
                selected: _tool == _EditTool.crop,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.crop),
              ),
              CapCutToolIcon(
                icon: Icons.rotate_right_rounded,
                label: 'Rotate',
                selected: _tool == _EditTool.rotate,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.rotate),
              ),
              CapCutToolIcon(
                icon: Icons.flip_rounded,
                label: 'Flip',
                enabled: atPos != null,
                onTap: atPos == null
                    ? null
                    : () => patch((c) => c.copyWith(flipH: !c.flipH)),
              ),
              CapCutToolIcon(
                icon: Icons.replay_rounded,
                label: 'Reverse',
                enabled: atPos != null,
                onTap: atPos == null
                    ? null
                    : () => notifier.setVideoClips(
                          ClipOps.toggleReverse(editor.videoClips, atPos.id),
                        ),
              ),
              CapCutToolIcon(
                icon: Icons.pause_circle_outline,
                label: 'Freeze',
                enabled: atPos != null,
                onTap: atPos == null
                    ? null
                    : () => notifier.setVideoClips(
                          ClipOps.freezeFrame(
                            editor.videoClips,
                            atPos.id,
                            position,
                          ),
                        ),
              ),
              CapCutToolIcon(
                icon: Icons.content_copy_rounded,
                label: 'Copy',
                enabled: atPos != null,
                onTap: atPos == null
                    ? null
                    : () => notifier.setVideoClips(
                          ClipOps.duplicate(editor.videoClips, atPos.id),
                        ),
              ),
              CapCutToolIcon(
                icon: Icons.animation_rounded,
                label: 'Trans',
                selected: _tool == _EditTool.transition,
                enabled: atPos != null,
                onTap: () => setState(() => _tool = _EditTool.transition),
              ),
              CapCutToolIcon(
                icon: Icons.auto_awesome,
                label: 'Enhance',
                enabled: atPos != null,
                onTap:
                    atPos == null ? null : () => patch(FeatureOps.autoEnhance),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            children: [
              if (atPos != null) ...[
                Text(
                  atPos.fileName.isEmpty ? 'Selected clip' : atPos.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${TimestampUtils.toUi(atPos.trimmedDuration)}'
                  '${atPos.reversed ? ' · REV' : ''}'
                  ' · ${atPos.speed.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Select a clip on the timeline',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              if (_tool == _EditTool.speed && atPos != null) ...[
                const Text(
                  'Speed',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const [0.5, 0.75, 1.0, 1.5, 2.0, 3.0])
                      ChoiceChip(
                        label: Text('${s}x'),
                        selected: (atPos.speed - s).abs() < 0.01,
                        onSelected: (_) => patch((c) => c.copyWith(speed: s)),
                        selectedColor: Colors.white24,
                      ),
                  ],
                ),
                Slider(
                  value: atPos.speed.clamp(0.25, 4.0),
                  min: 0.25,
                  max: 4.0,
                  onChanged: (v) => patch((c) => c.copyWith(speed: v)),
                ),
              ],
              if (_tool == _EditTool.volume && atPos != null)
                _editSlider(
                  'Volume ${(atPos.volume * 100).round()}%',
                  atPos.volume.clamp(0, 1),
                  0,
                  1,
                  (v) => patch((c) => c.copyWith(volume: v)),
                ),
              if (_tool == _EditTool.opacity && atPos != null)
                _editSlider(
                  'Opacity ${(atPos.opacity * 100).round()}%',
                  atPos.opacity.clamp(0, 1),
                  0,
                  1,
                  (v) => patch((c) => c.copyWith(opacity: v)),
                ),
              if (_tool == _EditTool.rotate && atPos != null) ...[
                _editSlider(
                  'Rotate ${atPos.rotationDeg.round()}°',
                  atPos.rotationDeg.clamp(-180, 180),
                  -180,
                  180,
                  (v) => patch((c) => c.copyWith(rotationDeg: v)),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final deg in const [0.0, 90.0, 180.0, -90.0])
                      ActionChip(
                        label: Text('${deg.round()}°'),
                        onPressed: () =>
                            patch((c) => c.copyWith(rotationDeg: deg)),
                      ),
                  ],
                ),
              ],
              if (_tool == _EditTool.crop && atPos != null) ...[
                _editSlider(
                  'Crop L',
                  atPos.cropLeft.clamp(0, 0.4),
                  0,
                  0.4,
                  (v) => patch((c) => c.copyWith(cropLeft: v)),
                ),
                _editSlider(
                  'Crop R',
                  atPos.cropRight.clamp(0, 0.4),
                  0,
                  0.4,
                  (v) => patch((c) => c.copyWith(cropRight: v)),
                ),
                _editSlider(
                  'Zoom ${atPos.zoom.toStringAsFixed(2)}x',
                  atPos.zoom.clamp(1.0, 3.0),
                  1.0,
                  3.0,
                  (v) => patch((c) => c.copyWith(zoom: v)),
                ),
              ],
              if (_tool == _EditTool.transition && atPos != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in ClipOps.transitions.entries)
                      ChoiceChip(
                        label:
                            Text(e.value, style: const TextStyle(fontSize: 11)),
                        selected: atPos.transitionOut == e.key,
                        onSelected: (_) =>
                            patch((c) => c.copyWith(transitionOut: e.key)),
                      ),
                  ],
                ),
              if (_tool == _EditTool.none) ...[
                const Text(
                  'Aspect ratio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in ClipOps.aspectRatios.entries)
                      ChoiceChip(
                        label: Text(e.key, style: const TextStyle(fontSize: 11)),
                        selected: editor.aspectRatio == e.key,
                        onSelected: (_) => notifier.setAspectRatio(e.key),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Snap to playhead',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  value: editor.snapEnabled,
                  activeThumbColor: AppColors.brand,
                  onChanged: notifier.setSnapEnabled,
                ),
                if (atPos != null) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'More',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.merge_type, size: 16),
                        label: const Text('Merge'),
                        onPressed: () => notifier.setVideoClips(
                          ClipOps.mergeAdjacent(editor.videoClips, atPos.id),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.ssid_chart, size: 16),
                        label: const Text('Speed ramp'),
                        onPressed: () => notifier.setVideoClips(
                          ClipOps.reflow(
                            FeatureOps.speedRamp(editor.videoClips, atPos.id),
                          ),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.graphic_eq, size: 16),
                        label: const Text('Beat cut'),
                        onPressed: () => notifier.setVideoClips(
                          FeatureOps.beatSplit(editor.videoClips, atPos.id),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.smartphone, size: 16),
                        label: const Text('Shorts'),
                        onPressed: () {
                          patch(FeatureOps.longToShorts);
                          notifier.setAspectRatio('9:16');
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _editSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}


class _AudioPanel extends ConsumerWidget {
  const _AudioPanel({
    required this.editor,
    this.onAddPreset,
  });

  final EditorState editor;
  final Future<void> Function(MediaPreset preset)? onAddPreset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionLabel('MUSIC / AUDIO'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Mute original video audio',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          value: editor.muteOriginalAudio,
          activeThumbColor: AppColors.brand,
          onChanged: notifier.setMuteOriginalAudio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Ducking (music under voice)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          value: editor.duckingEnabled,
          activeThumbColor: AppColors.brand,
          onChanged: notifier.setDuckingEnabled,
        ),
        Row(
          children: [
            Expanded(
              child: StudioButton(
                label: 'Auto Volume',
                icon: Icons.equalizer,
                filled: false,
                onPressed: notifier.normalizeAudioVolumes,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StudioButton(
                label: 'Add Fades',
                icon: Icons.linear_scale,
                filled: false,
                onPressed: editor.audioClips.isEmpty
                    ? null
                    : () => notifier.setAudioClips([
                          for (final a in editor.audioClips)
                            FeatureOps.withDefaultFades(a),
                        ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Voice FX', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in FeatureOps.voiceEffects.entries)
              ActionChip(
                label: Text(e.value, style: const TextStyle(fontSize: 11)),
                onPressed: editor.audioClips.isEmpty
                    ? null
                    : () => notifier.setAudioClips([
                          for (final a in editor.audioClips)
                            a.copyWith(effectId: e.key),
                        ]),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('MUSIC LIBRARY'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in MediaLibrary.music)
              ActionChip(
                avatar: Text(m.emoji),
                label: Text(m.name, style: const TextStyle(fontSize: 11)),
                onPressed: onAddPreset == null ? null : () => onAddPreset!(m),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('SFX LIBRARY'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in MediaLibrary.sfx)
              ActionChip(
                avatar: Text(m.emoji),
                label: Text(m.name, style: const TextStyle(fontSize: 11)),
                onPressed: onAddPreset == null ? null : () => onAddPreset!(m),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (editor.audioClips.isEmpty)
          const EmptyHint(
            icon: Icons.music_note_outlined,
            title: 'هیچ مۆسیقایەک نییە',
            subtitle: 'کتێبخانە یان Import بەکاربهێنە',
          )
        else
          for (final a in editor.audioClips)
            SoftCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.fileName.isEmpty ? 'Audio' : a.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Vol ${(a.volume * 100).round()}% · Fade ${a.fadeInMs}/${a.fadeOutMs}ms'
                    '${a.isVoiceover ? ' · VO' : ''}'
                    '${a.effectId != 'none' ? ' · ${a.effectId}' : ''}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    min: 0,
                    max: 1,
                    value: a.volume.clamp(0, 1),
                    onChanged: (v) {
                      notifier.setAudioClips([
                        for (final x in editor.audioClips)
                          if (x.id == a.id) x.copyWith(volume: v) else x,
                      ]);
                    },
                  ),
                  Text(
                    'Stretch ${a.speed.toStringAsFixed(2)}x',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    min: 0.5,
                    max: 2,
                    value: a.speed.clamp(0.5, 2),
                    onChanged: (v) {
                      notifier.setAudioClips([
                        for (final x in editor.audioClips)
                          if (x.id == a.id) x.copyWith(speed: v) else x,
                      ]);
                    },
                  ),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Mute'),
                        selected: a.muted,
                        onSelected: (v) => notifier.setAudioClips([
                          for (final x in editor.audioClips)
                            if (x.id == a.id) x.copyWith(muted: v) else x,
                        ]),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Solo'),
                        selected: a.solo,
                        onSelected: (v) => notifier.setAudioClips([
                          for (final x in editor.audioClips)
                            if (x.id == a.id) x.copyWith(solo: v) else x,
                        ]),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('VO'),
                        selected: a.isVoiceover,
                        onSelected: (v) => notifier.setAudioClips([
                          for (final x in editor.audioClips)
                            if (x.id == a.id) x.copyWith(isVoiceover: v) else x,
                        ]),
                      ),
                    ],
                  ),
                  Text(
                    'Fade in ${a.fadeInMs}ms',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    min: 0,
                    max: 2000,
                    value: a.fadeInMs.toDouble().clamp(0, 2000),
                    onChanged: (v) {
                      notifier.setAudioClips([
                        for (final x in editor.audioClips)
                          if (x.id == a.id)
                            x.copyWith(fadeInMs: v.round())
                          else
                            x,
                      ]);
                    },
                  ),
                  Text(
                    'Fade out ${a.fadeOutMs}ms',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    min: 0,
                    max: 2000,
                    value: a.fadeOutMs.toDouble().clamp(0, 2000),
                    onChanged: (v) {
                      notifier.setAudioClips([
                        for (final x in editor.audioClips)
                          if (x.id == a.id)
                            x.copyWith(fadeOutMs: v.round())
                          else
                            x,
                      ]);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => notifier.setAudioClips(
                        editor.audioClips.where((x) => x.id != a.id).toList(),
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _StickersPanel extends ConsumerWidget {
  const _StickersPanel({required this.editor, required this.position});

  final EditorState editor;
  final Duration position;

  static const _emojis = ['🔥', '😂', '❤️', '✨', '👏', '😍', '🎉', '💯', '⭐', '😱'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionLabel('STICKERS'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _emojis)
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.addSticker(
                    StickerItem.create(
                      emoji: e,
                      start: position,
                      end: position + const Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionLabel('OVERLAY FX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in FeatureOps.overlayEmojis)
              ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 18)),
                onPressed: () => notifier.addSticker(
                  StickerItem.create(
                    emoji: e,
                    start: position,
                    end: position + const Duration(seconds: 1),
                    scale: 1.4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionLabel('ALIGN / KEYFRAMES'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final mode in const ['left', 'center', 'right', 'top', 'bottom'])
              ActionChip(
                label: Text(mode, style: const TextStyle(fontSize: 11)),
                onPressed: editor.stickers.isEmpty
                    ? null
                    : () => notifier.setStickers(
                          FeatureOps.autoAlign(editor.stickers, mode: mode),
                        ),
              ),
            ActionChip(
              label: const Text('Animate', style: TextStyle(fontSize: 11)),
              onPressed: editor.stickers.isEmpty
                  ? null
                  : () => notifier.setStickers([
                        for (final s in editor.stickers)
                          s.copyWith(animated: true, scale: s.scale * 1.1),
                      ]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Blend overlays', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final e in FeatureOps.blendModes.entries)
              ActionChip(
                label: Text(e.value, style: const TextStyle(fontSize: 11)),
                onPressed: editor.stickers.isEmpty
                    ? null
                    : () => notifier.setStickers([
                          for (final s in editor.stickers)
                            s.copyWith(blendMode: e.key, opacity: 0.85),
                        ]),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionLabel('WATERMARK'),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: 'ناوی براند / واتەرمارک',
            isDense: true,
          ),
          controller: TextEditingController(text: editor.watermarkText)
            ..selection = TextSelection.collapsed(
              offset: editor.watermarkText.length,
            ),
          onSubmitted: notifier.setWatermarkText,
          onChanged: notifier.setWatermarkText,
        ),
        if (editor.stickers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${editor.stickers.length} sticker(s)',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _StyleStudio extends ConsumerWidget {
  const _StyleStudio({
    required this.editor,
    required this.fonts,
    required this.onPreset,
    required this.onStyle,
  });

  final EditorState editor;
  final List<FontOption> fonts;
  final ValueChanged<String> onPreset;
  final ValueChanged<SubtitleStyle> onStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(editorControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionLabel('PRESET'),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final preset in SubtitlePresetCatalog.all) ...[
                PresetCard(
                  name: preset.name,
                  selected: editor.presetId == preset.id,
                  onTap: () => onPreset(preset.id),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SectionLabel('TRENDING TEMPLATES'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in FeatureOps.trendingTemplateIds)
              ActionChip(
                label: Text(id, style: const TextStyle(fontSize: 11)),
                onPressed: () => onPreset(id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('BRAND KITS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final kit in FeatureOps.brandKits.values)
              ChoiceChip(
                label: Text(kit.name, style: const TextStyle(fontSize: 11)),
                selected: editor.brandKitId == kit.id,
                selectedColor: kit.primary.withValues(alpha: 0.25),
                onSelected: (_) => notifier.applyBrandKit(kit.id),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Text tracking (follow sticker)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          value: editor.textTracking,
          onChanged: notifier.setTextTracking,
        ),
        const SizedBox(height: 8),
        StudioButton(
          label: 'Auto lyrics style',
          icon: Icons.lyrics_outlined,
          filled: false,
          onPressed: () {
            final lyrics = FeatureOps.autoLyricsStyle();
            onPreset(lyrics.presetId);
            onStyle(lyrics.style);
          },
        ),
        const SizedBox(height: 8),
        StudioButton(
          label: 'Smart template fill',
          icon: Icons.dashboard_customize,
          filled: false,
          onPressed: () {
            final filled = FeatureOps.smartTemplateFill(
              editor.segments,
              editor.presetId,
            );
            ref.read(editorControllerProvider.notifier).setSegments(filled);
            onPreset(
              FeatureOps.trendingTemplateIds.isEmpty
                  ? 'neon'
                  : FeatureOps.trendingTemplateIds.first,
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionLabel('FONT'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: editor.style.fontFamily,
          items: [
            for (final f in fonts)
              DropdownMenuItem(value: f.family, child: Text(f.displayName)),
          ],
          onChanged: (family) {
            if (family == null) return;
            onStyle(editor.style.copyWith(fontFamily: family));
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'Size',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            Text(
              editor.style.fontSize.toStringAsFixed(0),
              style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        Slider(
          min: 28,
          max: 90,
          value: editor.style.fontSize.clamp(28, 90),
          onChanged: (v) => onStyle(editor.style.copyWith(fontSize: v)),
        ),
        Row(
          children: [
            const Text(
              'Position',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            Text(
              editor.style.positionY.toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        Slider(
          min: 0.45,
          max: 0.9,
          value: editor.style.positionY.clamp(0.45, 0.9),
          onChanged: (v) => onStyle(editor.style.copyWith(positionY: v)),
        ),
        const Text(
          'Text position presets',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final e in const [
              ('Top', 0.18),
              ('Mid', 0.45),
              ('Low', 0.72),
              ('Bottom', 0.86),
            ])
              ChoiceChip(
                label: Text(e.$1, style: const TextStyle(fontSize: 11)),
                selected: (editor.style.positionY - e.$2).abs() < 0.03,
                onSelected: (_) => onStyle(editor.style.copyWith(positionY: e.$2)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

class _EffectsGrid extends StatelessWidget {
  const _EffectsGrid({
    required this.selected,
    required this.onSelect,
  });

  final SubtitleAnimationType selected;
  final ValueChanged<SubtitleAnimationType> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (SubtitleAnimationType.none, Icons.block, 'None'),
      (SubtitleAnimationType.fade, Icons.blur_on, 'Fade'),
      (SubtitleAnimationType.pop, Icons.bubble_chart_outlined, 'Pop'),
      (SubtitleAnimationType.slideUp, Icons.arrow_upward, 'Slide Up'),
      (SubtitleAnimationType.slideLeft, Icons.arrow_back, 'Slide Left'),
      (SubtitleAnimationType.slideRight, Icons.arrow_forward, 'Slide Right'),
      (SubtitleAnimationType.wordByWord, Icons.lyrics_outlined, 'Karaoke'),
    ];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('CAPTION EFFECTS'),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                for (final item in items)
                  EffectTile(
                    icon: item.$2,
                    label: item.$3,
                    selected: selected == item.$1,
                    onTap: () => onSelect(item.$1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportPanel extends ConsumerWidget {
  const _ExportPanel({
    required this.quality,
    required this.exporting,
    required this.progress,
    required this.message,
    required this.onQuality,
    required this.onExportMp4,
    required this.onExportSrt,
    required this.onExportAss,
    this.onExportGif,
    this.onBatchExport,
    this.onExportProjectJson,
    this.onImportProjectJson,
  });

  final ExportQuality quality;
  final bool exporting;
  final double progress;
  final String message;
  final ValueChanged<ExportQuality> onQuality;
  final VoidCallback onExportMp4;
  final VoidCallback onExportSrt;
  final VoidCallback onExportAss;
  final VoidCallback? onExportGif;
  final VoidCallback? onBatchExport;
  final VoidCallback? onExportProjectJson;
  final VoidCallback? onImportProjectJson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorControllerProvider);
    final notifier = ref.read(editorControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionLabel('MP4 QUALITY'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in ExportQuality.values)
              QualityChip(
                label: '${q.label} · ${q.fps}fps',
                selected: quality == q,
                onTap: () => onQuality(q),
              ),
          ],
        ),
        if (editor != null) ...[
          const SizedBox(height: 12),
          const SectionLabel('FRAME RATE'),
          Wrap(
            spacing: 6,
            children: [
              for (final fps in const [24, 30, 60])
                ChoiceChip(
                  label: Text('$fps fps'),
                  selected: editor.exportFps == fps,
                  onSelected: (_) => notifier.setExportFps(fps),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Proxy / performance mode',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            value: editor.proxyMode,
            onChanged: notifier.setProxyMode,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hardware acceleration',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            value: editor.hwAccel,
            onChanged: notifier.setHwAccel,
          ),
          const SizedBox(height: 4),
          FutureBuilder(
            future: ref.read(apiKeyProvider.future),
            builder: (context, snap) {
              final hasKey = (snap.data ?? '').isNotEmpty;
              return SoftCard(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      hasKey ? Icons.verified : Icons.warning_amber,
                      color: hasKey ? AppColors.success : AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasKey
                            ? 'AI credits: Gemini key چالاکە'
                            : 'AI credits: API key زیاد بکە',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        if (exporting) ...[
          const SizedBox(height: 14),
          Text(
            message.isEmpty ? 'Rendering…' : message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              color: AppColors.brand,
              backgroundColor: AppColors.surfaceSoft,
            ),
          ),
        ],
        const SizedBox(height: 16),
        StudioButton(
          label: exporting ? 'Rendering…' : 'Export MP4',
          icon: Icons.movie_creation_outlined,
          busy: exporting,
          onPressed: exporting ? null : onExportMp4,
        ),
        const SizedBox(height: 10),
        StudioButton(
          label: 'Export GIF (3s)',
          icon: Icons.gif_box_outlined,
          filled: false,
          onPressed: exporting ? null : onExportGif,
        ),
        const SizedBox(height: 10),
        StudioButton(
          label: 'Batch: MP4 + SRT + ASS',
          icon: Icons.playlist_add_check,
          filled: false,
          onPressed: exporting ? null : onBatchExport,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StudioButton(
                label: 'Export JSON',
                icon: Icons.upload_file,
                filled: false,
                onPressed: onExportProjectJson,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StudioButton(
                label: 'Import JSON',
                icon: Icons.download,
                filled: false,
                onPressed: onImportProjectJson,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('SUBTITLE FILES'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StudioButton(
                label: 'SRT',
                icon: Icons.subtitles_outlined,
                filled: false,
                onPressed: onExportSrt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StudioButton(
                label: 'ASS',
                icon: Icons.style_outlined,
                filled: false,
                onPressed: onExportAss,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CaptionTextPanel extends StatelessWidget {
  const CaptionTextPanel({
    super.key,
    required this.segments,
    required this.activeId,
    required this.mediaDuration,
    required this.onTap,
    required this.onChanged,
    required this.onDelete,
    required this.onSplit,
    required this.onMergeNext,
    required this.onAdd,
    this.onRemoveFillers,
    this.onSplitSentences,
  });

  final List<SubtitleSegment> segments;
  final String? activeId;
  final Duration mediaDuration;
  final ValueChanged<SubtitleSegment> onTap;
  final ValueChanged<SubtitleSegment> onChanged;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSplit;
  final ValueChanged<String> onMergeNext;
  final VoidCallback onAdd;
  final VoidCallback? onRemoveFillers;
  final VoidCallback? onSplitSentences;

  @override
  Widget build(BuildContext context) {
    final sorted = SubtitleOps.sorted(segments);
    if (sorted.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            child: Row(
              children: [
                const Text(
                  '0 CAPTIONS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const Expanded(
            child: EmptyHint(
              icon: Icons.subtitles_outlined,
              title: 'No captions yet',
              subtitle: 'Tap Captions chip or Captions tab → Auto Captions',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
          child: Row(
            children: [
              Text(
                '${sorted.length} CAPTIONS',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (onRemoveFillers != null)
                IconButton(
                  tooltip: 'Remove fillers',
                  onPressed: onRemoveFillers,
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                ),
              if (onSplitSentences != null)
                IconButton(
                  tooltip: 'Split sentences',
                  onPressed: onSplitSentences,
                  icon: const Icon(Icons.short_text, size: 18),
                ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final s = sorted[index];
              return _SegmentEditor(
                key: ValueKey(s.id),
                segment: s,
                selected: s.id == activeId,
                mediaDuration: mediaDuration,
                onTap: () => onTap(s),
                onChanged: onChanged,
                onDelete: () => onDelete(s.id),
                onSplit: () => onSplit(s.id),
                onMergeNext: () => onMergeNext(s.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SegmentEditor extends StatefulWidget {
  const _SegmentEditor({
    super.key,
    required this.segment,
    required this.selected,
    required this.mediaDuration,
    required this.onTap,
    required this.onChanged,
    required this.onDelete,
    required this.onSplit,
    required this.onMergeNext,
  });

  final SubtitleSegment segment;
  final bool selected;
  final Duration mediaDuration;
  final VoidCallback onTap;
  final ValueChanged<SubtitleSegment> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final VoidCallback onMergeNext;

  @override
  State<_SegmentEditor> createState() => _SegmentEditorState();
}

class _SegmentEditorState extends State<_SegmentEditor> {
  late final TextEditingController _text;

  static const _step = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.segment.text);
  }

  @override
  void didUpdateWidget(covariant _SegmentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.id != widget.segment.id ||
        oldWidget.segment.text != widget.segment.text) {
      _text.text = widget.segment.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _commitText() {
    final next = _text.text.trim();
    if (next.isEmpty || next == widget.segment.text) return;
    widget.onChanged(widget.segment.copyWith(text: next));
  }

  void _nudgeStart(Duration delta) {
    var start = widget.segment.start + delta;
    if (start < Duration.zero) start = Duration.zero;
    if (widget.segment.end - start < SubtitleOps.minDuration) {
      start = widget.segment.end - SubtitleOps.minDuration;
    }
    widget.onChanged(widget.segment.copyWith(start: start));
  }

  void _nudgeEnd(Duration delta) {
    var end = widget.segment.end + delta;
    if (end > widget.mediaDuration) end = widget.mediaDuration;
    if (end - widget.segment.start < SubtitleOps.minDuration) {
      end = widget.segment.start + SubtitleOps.minDuration;
    }
    widget.onChanged(widget.segment.copyWith(end: end));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.selected
            ? AppColors.brand.withValues(alpha: 0.1)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.selected ? AppColors.brand : AppColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Column(
              children: [
                TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'ژێرنووس بنووسە…',
                    filled: true,
                    fillColor: Colors.black26,
                  ),
                  onEditingComplete: _commitText,
                  onTapOutside: (_) => _commitText(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StepperChip(
                        label: 'In',
                        value: TimestampUtils.toUi(widget.segment.start),
                        onMinus: () => _nudgeStart(-_step),
                        onPlus: () => _nudgeStart(_step),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StepperChip(
                        label: 'Out',
                        value: TimestampUtils.toUi(widget.segment.end),
                        onMinus: () => _nudgeEnd(-_step),
                        onPlus: () => _nudgeEnd(_step),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _ActionBtn(
                      icon: Icons.call_split,
                      label: 'Split',
                      onTap: widget.onSplit,
                    ),
                    _ActionBtn(
                      icon: Icons.merge_type,
                      label: 'Merge',
                      onTap: widget.onMergeNext,
                    ),
                    _ActionBtn(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      danger: true,
                      onTap: widget.onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        icon: Icon(
          icon,
          size: 16,
          color: danger ? AppColors.danger : AppColors.textSecondary,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: danger ? AppColors.danger : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
