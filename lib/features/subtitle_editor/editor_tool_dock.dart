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

  /// CapCut primary toolbar — equal-width icons.
  static const _items = <(EditorTab, IconData, String)>[
    (EditorTab.edit, Icons.content_cut_rounded, 'Edit'),
    (EditorTab.text, Icons.closed_caption_rounded, 'Text'),
    (EditorTab.style, Icons.auto_awesome_outlined, 'Effect'),
    (EditorTab.audio, Icons.music_note_rounded, 'Audio'),
    (EditorTab.stickers, Icons.layers_outlined, 'Overlay'),
    (EditorTab.tools, Icons.apps_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: _DockItem(
                icon: item.$2,
                label: item.$3,
                selected: tab == item.$1 ||
                    (item.$1 == EditorTab.tools && tab == EditorTab.ai) ||
                    (item.$1 == EditorTab.style && tab == EditorTab.animation),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTab(item.$1);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF6B6B6B);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.05,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// CapCut Level-1 toolbar for any dock tab: « back + section tools + optional panel.
class CapCutTabContextBar extends ConsumerStatefulWidget {
  const CapCutTabContextBar({
    super.key,
    required this.tab,
    required this.editor,
    required this.position,
    required this.onBack,
    required this.onSeek,
    this.onOpenTab,
    this.onAutoCaptions,
    this.onImportSrt,
    this.onImportMedia,
    this.onExtractAudio,
    this.onBackup,
    this.onOpenExport,
    this.onAddPreset,
  });

  final EditorTab tab;
  final EditorState editor;
  final Duration position;
  final VoidCallback onBack;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<EditorTab>? onOpenTab;
  final VoidCallback? onAutoCaptions;
  final VoidCallback? onImportSrt;
  final VoidCallback? onImportMedia;
  final VoidCallback? onExtractAudio;
  final VoidCallback? onBackup;
  final VoidCallback? onOpenExport;
  final Future<void> Function(MediaPreset preset)? onAddPreset;

  @override
  ConsumerState<CapCutTabContextBar> createState() =>
      _CapCutTabContextBarState();
}

/// CapCut Text sub-modes: hub chooser → edit captions list → style.
enum _TextSub { hub, edit, style }

/// Edit-only wrapper kept for call-site clarity.
class CapCutEditContextBar extends StatelessWidget {
  const CapCutEditContextBar({
    super.key,
    required this.editor,
    required this.position,
    required this.onBack,
    required this.onSeek,
    this.onAutoCaptions,
    this.onImportSrt,
    this.onImportMedia,
    this.onExtractAudio,
    this.onBackup,
    this.onOpenExport,
    this.onAddPreset,
  });

  final EditorState editor;
  final Duration position;
  final VoidCallback onBack;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onAutoCaptions;
  final VoidCallback? onImportSrt;
  final VoidCallback? onImportMedia;
  final VoidCallback? onExtractAudio;
  final VoidCallback? onBackup;
  final VoidCallback? onOpenExport;
  final Future<void> Function(MediaPreset preset)? onAddPreset;

  @override
  Widget build(BuildContext context) {
    return CapCutTabContextBar(
      tab: EditorTab.edit,
      editor: editor,
      position: position,
      onBack: onBack,
      onSeek: onSeek,
      onAutoCaptions: onAutoCaptions,
      onImportSrt: onImportSrt,
      onImportMedia: onImportMedia,
      onExtractAudio: onExtractAudio,
      onBackup: onBackup,
      onOpenExport: onOpenExport,
      onAddPreset: onAddPreset,
    );
  }
}

enum _CtxTool {
  none,
  volume,
  fade,
  speed,
  opacity,
  crop,
  rotate,
  transition,
  fontSize,
  positionY,
}

class _CapCutTabContextBarState extends ConsumerState<CapCutTabContextBar> {
  _CtxTool _tool = _CtxTool.none;
  bool _panelOpen = true;
  _TextSub _textSub = _TextSub.hub;

  @override
  void didUpdateWidget(covariant CapCutTabContextBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _tool = _CtxTool.none;
      _panelOpen = widget.tab != EditorTab.edit;
      if (widget.tab == EditorTab.text) {
        _textSub = widget.editor.segments.isEmpty
            ? _TextSub.hub
            : (widget.editor.activeSegmentId != null
                ? _TextSub.edit
                : _TextSub.hub);
      }
    } else if (widget.tab == EditorTab.text) {
      // CapCut: selecting a caption clip jumps into Edit captions.
      final prevId = oldWidget.editor.activeSegmentId;
      final nextId = widget.editor.activeSegmentId;
      if (nextId != null && nextId != prevId && _textSub == _TextSub.hub) {
        _textSub = _TextSub.edit;
        _panelOpen = true;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _panelOpen = widget.tab != EditorTab.edit;
    if (widget.tab == EditorTab.text) {
      _textSub = widget.editor.segments.isEmpty
          ? _TextSub.hub
          : (widget.editor.activeSegmentId != null
              ? _TextSub.edit
              : _TextSub.hub);
    }
  }

  double get _panelHeight => switch (widget.tab) {
        EditorTab.text => switch (_textSub) {
            _TextSub.hub => 168.0,
            _TextSub.edit => 260.0,
            _TextSub.style => 240.0,
          },
        EditorTab.style || EditorTab.animation => 240.0,
        EditorTab.audio => 200.0,
        EditorTab.stickers => 180.0,
        EditorTab.tools || EditorTab.ai => 240.0,
        _ => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final position = widget.position;
    final notifier = ref.read(editorControllerProvider.notifier);
    VideoClip? atPos;
    for (final c in editor.videoClips) {
      if (c.id == editor.activeClipId) {
        atPos = c;
        break;
      }
    }
    atPos ??= ClipOps.atPosition(editor.videoClips, position);

    void patch(VideoClip Function(VideoClip) fn) {
      if (atPos == null) return;
      notifier.setActiveClip(atPos.id);
      notifier.setVideoClips(ClipOps.update(editor.videoClips, atPos.id, fn));
    }

    final sliderH = _tool == _CtxTool.none ? 0.0 : 52.0;
    final showPanel = _panelOpen && _panelHeight > 0;

    return ColoredBox(
      color: const Color(0xFF121212),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPanel)
            SizedBox(
              height: _panelHeight,
              child: _sectionPanel(editor, position, notifier),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: sliderH,
            child: sliderH == 0
                ? const SizedBox.shrink()
                : _ctxSlider(editor, atPos, patch, notifier),
          ),
          SizedBox(
            height: 72,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onBack();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 44,
                    height: 72,
                    child: Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 8),
                    children: _toolsForTab(editor, position, atPos, patch, notifier),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionPanel(
    EditorState editor,
    Duration position,
    EditorController notifier,
  ) {
    final fonts = ref.watch(fontServiceProvider).availableFonts;
    SubtitleSegment? active;
    for (final s in editor.segments) {
      if (s.id == editor.activeSegmentId) {
        active = s;
        break;
      }
    }
    active ??= SubtitleOps.activeAt(editor.segments, position);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0E),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      child: switch (widget.tab) {
        EditorTab.text => switch (_textSub) {
            _TextSub.hub => _CapCutTextHub(
                exporting: editor.isExporting,
                hasCaptions: editor.segments.isNotEmpty,
                onAddText: () => _addManualText(notifier, position),
                onAutoCaptions: widget.onAutoCaptions,
                onTemplates: () => setState(() {
                      _textSub = _TextSub.style;
                      _panelOpen = true;
                    }),
                onImportSrt: widget.onImportSrt,
                onEditCaptions: editor.segments.isEmpty
                    ? null
                    : () => setState(() {
                          _textSub = _TextSub.edit;
                          _panelOpen = true;
                        }),
              ),
            _TextSub.edit => CaptionTextPanel(
                segments: editor.segments,
                activeId: active?.id ?? editor.activeSegmentId,
                mediaDuration: editor.timelineDuration,
                exporting: editor.isExporting,
                showToolbar: false,
                onTap: (s) {
                  notifier.setActiveSegment(s.id);
                  widget.onSeek(s.start);
                },
                onChanged: notifier.updateSegment,
                onDelete: (id) => notifier.setSegments(
                  SubtitleOps.delete(editor.segments, id),
                ),
                onSplit: (id) => notifier.setSegments(
                  SubtitleOps.split(editor.segments, id),
                ),
                onMergeNext: (id) {
                  final sorted = SubtitleOps.sorted(editor.segments);
                  final i = sorted.indexWhere((s) => s.id == id);
                  if (i < 0 || i >= sorted.length - 1) return;
                  notifier.setSegments(
                    SubtitleOps.merge(sorted, sorted[i].id, sorted[i + 1].id),
                  );
                },
                onAdd: () => _addManualText(notifier, position),
                onRemoveFillers: () => notifier.setSegments(
                  SubtitleOps.removeFillers(editor.segments),
                ),
                onSplitSentences: () => notifier.setSegments(
                  SubtitleOps.splitBySentences(editor.segments),
                ),
                onAutoCaptions: widget.onAutoCaptions,
                onImportSrt: widget.onImportSrt,
              ),
            _TextSub.style => _StyleStudio(
                editor: editor,
                fonts: fonts,
                onPreset: notifier.applyPreset,
                onStyle: notifier.updateStyle,
              ),
          },
        EditorTab.style || EditorTab.animation => _StyleStudio(
            editor: editor,
            fonts: fonts,
            onPreset: notifier.applyPreset,
            onStyle: notifier.updateStyle,
          ),
        EditorTab.audio => _AudioPanel(
            editor: editor,
            onAddPreset: widget.onAddPreset,
          ),
        EditorTab.stickers => _StickersPanel(
            editor: editor,
            position: position,
          ),
        EditorTab.tools || EditorTab.ai => FeatureBrowserPanel(
            editor: editor,
            position: position,
            onOpenTab: (t) {
              // Stay in More context; primary tabs close via dock back.
              if (t == EditorTab.tools || t == EditorTab.ai) return;
              widget.onBack();
            },
            onImportMedia: widget.onImportMedia,
            onImportSrt: widget.onImportSrt,
            onExtractAudio: widget.onExtractAudio,
            onBackup: widget.onBackup,
            onAutoCaptions: widget.onAutoCaptions,
            onOpenExport: widget.onOpenExport,
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  List<Widget> _toolsForTab(
    EditorState editor,
    Duration position,
    VideoClip? atPos,
    void Function(VideoClip Function(VideoClip)) patch,
    EditorController notifier,
  ) {
    CapCutToolIcon browse() => CapCutToolIcon(
          icon: Icons.grid_view_rounded,
          label: 'Panel',
          selected: _panelOpen,
          onTap: () => setState(() => _panelOpen = !_panelOpen),
        );

    switch (widget.tab) {
      case EditorTab.edit:
        return _editTools(editor, position, atPos, patch, notifier);
      case EditorTab.text:
        return _textTools(editor, position, notifier);
      case EditorTab.style:
      case EditorTab.animation:
        return [
          browse(),
          CapCutToolIcon(
            icon: Icons.style_outlined,
            label: 'Style',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.format_size_rounded,
            label: 'Size',
            selected: _tool == _CtxTool.fontSize,
            onTap: () => setState(() =>
                _tool = _tool == _CtxTool.fontSize
                    ? _CtxTool.none
                    : _CtxTool.fontSize),
          ),
          CapCutToolIcon(
            icon: Icons.vertical_align_center_rounded,
            label: 'Position',
            selected: _tool == _CtxTool.positionY,
            onTap: () => setState(() =>
                _tool = _tool == _CtxTool.positionY
                    ? _CtxTool.none
                    : _CtxTool.positionY),
          ),
          CapCutToolIcon(
            icon: Icons.animation_outlined,
            label: 'Motion',
            selected: editor.animation.type != SubtitleAnimationType.none,
            onTap: () {
              notifier.setAnimation(
                editor.animation.type == SubtitleAnimationType.none
                    ? SubtitleAnimationConfig.fade
                    : SubtitleAnimationConfig.none,
              );
            },
          ),
          CapCutToolIcon(
            icon: Icons.auto_awesome_outlined,
            label: 'Preset',
            onTap: () {
              setState(() => _panelOpen = true);
              notifier.applyPreset(
                FeatureOps.trendingTemplateIds.isEmpty
                    ? 'neon'
                    : FeatureOps.trendingTemplateIds.first,
              );
            },
          ),
        ];
      case EditorTab.audio:
        return [
          browse(),
          CapCutToolIcon(
            icon: Icons.volume_off_outlined,
            label: 'Mute',
            selected: editor.muteOriginalAudio,
            onTap: () =>
                notifier.setMuteOriginalAudio(!editor.muteOriginalAudio),
          ),
          CapCutToolIcon(
            icon: Icons.graphic_eq_rounded,
            label: 'Duck',
            selected: editor.duckingEnabled,
            onTap: () => notifier.setDuckingEnabled(!editor.duckingEnabled),
          ),
          CapCutToolIcon(
            icon: Icons.equalizer_rounded,
            label: 'Normalize',
            onTap: notifier.normalizeAudioVolumes,
          ),
          CapCutToolIcon(
            icon: Icons.linear_scale,
            label: 'Fades',
            enabled: editor.audioClips.isNotEmpty,
            onTap: editor.audioClips.isEmpty
                ? null
                : () => notifier.setAudioClips([
                      for (final a in editor.audioClips)
                        FeatureOps.withDefaultFades(a),
                    ]),
          ),
          CapCutToolIcon(
            icon: Icons.library_music_outlined,
            label: 'Music',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.audio_file_outlined,
            label: 'Extract',
            enabled: widget.onExtractAudio != null,
            onTap: widget.onExtractAudio,
          ),
        ];
      case EditorTab.stickers:
        return [
          browse(),
          CapCutToolIcon(
            icon: Icons.sticky_note_2_outlined,
            label: 'Sticker',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.add_box_outlined,
            label: 'Add',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.align_horizontal_center,
            label: 'Align',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.delete_outline_rounded,
            label: 'Clear',
            danger: true,
            enabled: editor.stickers.isNotEmpty,
            onTap: editor.stickers.isEmpty
                ? null
                : () => notifier.setStickers([]),
          ),
        ];
      case EditorTab.tools:
      case EditorTab.ai:
        return [
          browse(),
          CapCutToolIcon(
            icon: Icons.auto_awesome_rounded,
            label: 'AI',
            onTap: () => setState(() => _panelOpen = true),
          ),
          CapCutToolIcon(
            icon: Icons.closed_caption_rounded,
            label: 'Captions',
            enabled: widget.onAutoCaptions != null,
            onTap: widget.onAutoCaptions,
          ),
          CapCutToolIcon(
            icon: Icons.upload_file_rounded,
            label: 'Import',
            enabled: widget.onImportMedia != null,
            onTap: widget.onImportMedia,
          ),
          CapCutToolIcon(
            icon: Icons.ios_share_rounded,
            label: 'Export',
            enabled: widget.onOpenExport != null,
            onTap: widget.onOpenExport,
          ),
          CapCutToolIcon(
            icon: Icons.backup_outlined,
            label: 'Backup',
            enabled: widget.onBackup != null,
            onTap: widget.onBackup,
          ),
        ];
      case EditorTab.export:
        return [browse()];
    }
  }

  void _addManualText(EditorController notifier, Duration position) {
    final next = SubtitleOps.add(
      widget.editor.segments,
      start: position,
      end: position + const Duration(seconds: 2),
      text: 'Text',
    );
    notifier.setSegments(next);
    final added = SubtitleOps.sorted(next).lastOrNull;
    if (added != null) notifier.setActiveSegment(added.id);
    setState(() {
      _textSub = _TextSub.edit;
      _panelOpen = true;
    });
  }

  /// CapCut Text toolbar: hub chooser vs selection tools (Edit / Style / Animation).
  List<Widget> _textTools(
    EditorState editor,
    Duration position,
    EditorController notifier,
  ) {
    final hasActive = editor.activeSegmentId != null;
    final hasCaptions = editor.segments.isNotEmpty;

    // CapCut hub tools when nothing selected / first entry.
    if (_textSub == _TextSub.hub || (!hasActive && !hasCaptions)) {
      return [
        CapCutToolIcon(
          icon: Icons.title_rounded,
          label: 'Add text',
          onTap: () => _addManualText(notifier, position),
        ),
        CapCutToolIcon(
          icon: Icons.closed_caption_rounded,
          label: editor.isExporting ? '…' : 'Captions',
          enabled: !editor.isExporting && widget.onAutoCaptions != null,
          onTap: editor.isExporting
              ? null
              : () {
                  setState(() {
                    _textSub = _TextSub.edit;
                    _panelOpen = true;
                  });
                  widget.onAutoCaptions?.call();
                },
        ),
        CapCutToolIcon(
          icon: Icons.auto_awesome_outlined,
          label: 'Templates',
          onTap: () => setState(() {
                _textSub = _TextSub.style;
                _panelOpen = true;
              }),
        ),
        CapCutToolIcon(
          icon: Icons.upload_file_rounded,
          label: 'Import',
          enabled: widget.onImportSrt != null,
          onTap: widget.onImportSrt,
        ),
        if (hasCaptions)
          CapCutToolIcon(
            icon: Icons.edit_note_rounded,
            label: 'Edit',
            selected: _textSub == _TextSub.edit,
            onTap: () => setState(() {
                  _textSub = _TextSub.edit;
                  _panelOpen = true;
                }),
          ),
      ];
    }

    // CapCut selection tools when a caption/text clip is focused.
    return [
      CapCutToolIcon(
        icon: Icons.edit_rounded,
        label: 'Edit',
        selected: _textSub == _TextSub.edit,
        onTap: () => setState(() {
              _textSub = _TextSub.edit;
              _panelOpen = true;
            }),
      ),
      CapCutToolIcon(
        icon: Icons.style_outlined,
        label: 'Style',
        selected: _textSub == _TextSub.style,
        onTap: () => setState(() {
              _textSub = _TextSub.style;
              _panelOpen = true;
            }),
      ),
      CapCutToolIcon(
        icon: Icons.animation_outlined,
        label: 'Animation',
        selected: editor.animation.type != SubtitleAnimationType.none,
        onTap: () {
          notifier.setAnimation(
            editor.animation.type == SubtitleAnimationType.none
                ? SubtitleAnimationConfig.fade
                : SubtitleAnimationConfig.pop,
          );
          setState(() {
            _textSub = _TextSub.style;
            _panelOpen = true;
          });
        },
      ),
      CapCutToolIcon(
        icon: Icons.format_size_rounded,
        label: 'Size',
        selected: _tool == _CtxTool.fontSize,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.fontSize
                ? _CtxTool.none
                : _CtxTool.fontSize),
      ),
      CapCutToolIcon(
        icon: Icons.content_cut_rounded,
        label: 'Split',
        enabled: hasActive,
        onTap: !hasActive
            ? null
            : () => notifier.setSegments(
                  SubtitleOps.split(editor.segments, editor.activeSegmentId!),
                ),
      ),
      CapCutToolIcon(
        icon: Icons.copy_outlined,
        label: 'Copy',
        enabled: hasActive,
        onTap: !hasActive
            ? null
            : () {
                SubtitleSegment? src;
                for (final s in editor.segments) {
                  if (s.id == editor.activeSegmentId) {
                    src = s;
                    break;
                  }
                }
                if (src == null) return;
                final gap = src.end - src.start;
                final next = SubtitleOps.add(
                  editor.segments,
                  start: src.end,
                  end: src.end + gap,
                  text: src.text,
                );
                notifier.setSegments(next);
              },
      ),
      CapCutToolIcon(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        danger: true,
        enabled: hasActive,
        onTap: !hasActive
            ? null
            : () => notifier.setSegments(
                  SubtitleOps.delete(editor.segments, editor.activeSegmentId!),
                ),
      ),
      CapCutToolIcon(
        icon: Icons.apps_rounded,
        label: 'More',
        onTap: () => setState(() {
              _textSub = _TextSub.hub;
              _panelOpen = true;
            }),
      ),
    ];
  }

  List<Widget> _editTools(
    EditorState editor,
    Duration position,
    VideoClip? atPos,
    void Function(VideoClip Function(VideoClip)) patch,
    EditorController notifier,
  ) {
    return [
      CapCutToolIcon(
        icon: Icons.volume_up_outlined,
        label: 'Volume',
        selected: _tool == _CtxTool.volume,
        enabled: atPos != null,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.volume ? _CtxTool.none : _CtxTool.volume),
      ),
      CapCutToolIcon(
        icon: Icons.linear_scale,
        label: 'Fade',
        selected: _tool == _CtxTool.fade,
        enabled: atPos != null,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.fade ? _CtxTool.none : _CtxTool.fade),
      ),
      CapCutToolIcon(
        icon: Icons.content_cut,
        label: 'Split',
        enabled: atPos != null,
        onTap: atPos == null
            ? null
            : () => notifier.setVideoClips(
                  ClipOps.split(editor.videoClips, atPos.id, position),
                ),
      ),
      CapCutToolIcon(
        icon: Icons.delete_outline,
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
        icon: Icons.speed,
        label: 'Speed',
        selected: _tool == _CtxTool.speed,
        enabled: atPos != null,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.speed ? _CtxTool.none : _CtxTool.speed),
      ),
      CapCutToolIcon(
        icon: Icons.opacity,
        label: 'Opacity',
        selected: _tool == _CtxTool.opacity,
        enabled: atPos != null,
        onTap: () => setState(() => _tool =
            _tool == _CtxTool.opacity ? _CtxTool.none : _CtxTool.opacity),
      ),
      CapCutToolIcon(
        icon: Icons.crop,
        label: 'Crop',
        selected: _tool == _CtxTool.crop,
        enabled: atPos != null,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.crop ? _CtxTool.none : _CtxTool.crop),
      ),
      CapCutToolIcon(
        icon: Icons.rotate_right,
        label: 'Rotate',
        selected: _tool == _CtxTool.rotate,
        enabled: atPos != null,
        onTap: () => setState(() =>
            _tool = _tool == _CtxTool.rotate ? _CtxTool.none : _CtxTool.rotate),
      ),
      CapCutToolIcon(
        icon: Icons.flip,
        label: 'Flip',
        enabled: atPos != null,
        onTap: atPos == null
            ? null
            : () => patch((c) => c.copyWith(flipH: !c.flipH)),
      ),
      CapCutToolIcon(
        icon: Icons.copy_outlined,
        label: 'Copy',
        enabled: atPos != null,
        onTap: atPos == null
            ? null
            : () => notifier.setVideoClips(
                  ClipOps.duplicate(editor.videoClips, atPos.id),
                ),
      ),
      CapCutToolIcon(
        icon: Icons.animation_outlined,
        label: 'Trans',
        selected: _tool == _CtxTool.transition,
        enabled: atPos != null,
        onTap: () => setState(() => _tool = _tool == _CtxTool.transition
            ? _CtxTool.none
            : _CtxTool.transition),
      ),
    ];
  }

  Widget _ctxSlider(
    EditorState editor,
    VideoClip? atPos,
    void Function(VideoClip Function(VideoClip)) patch,
    EditorController notifier,
  ) {
    if (_tool == _CtxTool.fontSize) {
      return _slimSlider(
        'Size ${editor.style.fontSize.toStringAsFixed(0)}',
        editor.style.fontSize.clamp(24, 120),
        24,
        120,
        (v) => notifier.updateStyle(editor.style.copyWith(fontSize: v)),
      );
    }
    if (_tool == _CtxTool.positionY) {
      return _slimSlider(
        'Vertical ${editor.style.positionY.toStringAsFixed(2)}',
        editor.style.positionY.clamp(0.08, 0.92),
        0.08,
        0.92,
        (v) => notifier.updateStyle(editor.style.copyWith(positionY: v)),
      );
    }
    if (atPos == null) return const SizedBox.shrink();
    switch (_tool) {
      case _CtxTool.volume:
        return _slimSlider(
          'Volume ${(atPos.volume * 100).round()}%',
          atPos.volume.clamp(0, 1),
          0,
          1,
          (v) => patch((c) => c.copyWith(volume: v)),
        );
      case _CtxTool.fade:
        return _slimSlider(
          'Fade ${(atPos.fadeInMs + atPos.fadeOutMs) ~/ 2}ms',
          ((atPos.fadeInMs + atPos.fadeOutMs) / 2).clamp(0, 2000).toDouble(),
          0,
          2000,
          (v) {
            final ms = v.round();
            patch((c) => c.copyWith(fadeInMs: ms, fadeOutMs: ms));
          },
        );
      case _CtxTool.speed:
        return _slimSlider(
          'Speed ${atPos.speed.toStringAsFixed(2)}x',
          atPos.speed.clamp(0.25, 4),
          0.25,
          4,
          (v) => patch((c) => c.copyWith(speed: v)),
        );
      case _CtxTool.opacity:
        return _slimSlider(
          'Opacity ${(atPos.opacity * 100).round()}%',
          atPos.opacity.clamp(0, 1),
          0,
          1,
          (v) => patch((c) => c.copyWith(opacity: v)),
        );
      case _CtxTool.crop:
        return _slimSlider(
          'Zoom ${atPos.zoom.toStringAsFixed(2)}x',
          atPos.zoom.clamp(1, 3),
          1,
          3,
          (v) => patch((c) => c.copyWith(zoom: v)),
        );
      case _CtxTool.rotate:
        return _slimSlider(
          'Rotate ${atPos.rotationDeg.round()}°',
          atPos.rotationDeg.clamp(-180, 180),
          -180,
          180,
          (v) => patch((c) => c.copyWith(rotationDeg: v)),
        );
      case _CtxTool.transition:
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          children: [
            for (final e in ClipOps.transitions.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11)),
                  selected: atPos.transitionOut == e.key,
                  selectedColor: Colors.white24,
                  onSelected: (_) =>
                      patch((c) => c.copyWith(transitionOut: e.key)),
                ),
              ),
          ],
        );
      case _CtxTool.none:
      case _CtxTool.fontSize:
      case _CtxTool.positionY:
        return const SizedBox.shrink();
    }
  }

  Widget _slimSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB0B0B0),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0xFF333333),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
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
    this.onAutoCaptions,
    this.onOpenExport,
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
  final VoidCallback? onAutoCaptions;
  final VoidCallback? onOpenExport;

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
        color: const Color(0xFF0E0E0E),
        border: Border(
          left: asSidePanel
              ? const BorderSide(color: Color(0xFF1A1A1A))
              : BorderSide.none,
          top: asSidePanel
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF1A1A1A)),
        ),
      ),
      child: CapCutSheetChrome(
        title: switch (tab) {
          EditorTab.tools => 'More',
          EditorTab.edit => 'Edit',
          EditorTab.text => 'Text',
          EditorTab.style => 'Effect',
          EditorTab.animation => 'Effect',
          EditorTab.audio => 'Audio',
          EditorTab.stickers => 'Overlay',
          EditorTab.ai => 'AI tools',
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
            onAutoCaptions: onAutoCaptions,
            onOpenExport: onOpenExport,
          ),
        EditorTab.edit => _EditClipPanel(editor: editor, position: position),
        EditorTab.text => CaptionTextPanel(
            segments: editor.segments,
            activeId: active?.id ?? editor.activeSegmentId,
            mediaDuration: editor.timelineDuration,
            exporting: editor.isExporting,
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
            onAutoCaptions: onAutoCaptions,
            onImportSrt: onImportSrt,
          ),
        EditorTab.style || EditorTab.animation => _StyleStudio(
            editor: editor,
            fonts: fonts,
            onPreset: notifier.applyPreset,
            onStyle: notifier.updateStyle,
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
        // CapCut horizontal edit tools
        ColoredBox(
          color: const Color(0xFF0E0E0E),
          child: SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                CapCutToolIcon(
                  icon: Icons.content_cut_rounded,
                  label: 'Split',
                  enabled: atPos != null,
                  onTap: atPos == null
                      ? null
                      : () => notifier.setVideoClips(
                            ClipOps.split(
                                editor.videoClips, atPos.id, position),
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
                  icon: Icons.pause_circle_outline_rounded,
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
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  enabled: atPos != null,
                  onTap: atPos == null
                      ? null
                      : () => notifier.setVideoClips(
                            ClipOps.duplicate(editor.videoClips, atPos.id),
                          ),
                ),
                CapCutToolIcon(
                  icon: Icons.animation_outlined,
                  label: 'Trans',
                  selected: _tool == _EditTool.transition,
                  enabled: atPos != null,
                  onTap: () => setState(() => _tool = _EditTool.transition),
                ),
                CapCutToolIcon(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Enhance',
                  enabled: atPos != null,
                  onTap: atPos == null
                      ? null
                      : () => patch(FeatureOps.autoEnhance),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFF1C1C1C)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            children: [
              if (atPos == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Select a clip on the timeline',
                    style: TextStyle(
                      color: Color(0xFF6B6B6B),
                      fontSize: 12,
                    ),
                  ),
                )
              else if (_tool == _EditTool.none) ...[
                Text(
                  atPos.fileName.isEmpty ? 'Selected clip' : atPos.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF8E8E8E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${TimestampUtils.toUi(atPos.trimmedDuration)}'
                  '${atPos.reversed ? ' · REV' : ''}'
                  ' · ${atPos.speed.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: Color(0xFF5C5C5C),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
              ],
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
                const CapCutSectionTitle('ASPECT'),
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
                        selectedColor: Colors.white24,
                        backgroundColor: const Color(0xFF1C1C1C),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Snap to playhead',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  value: editor.snapEnabled,
                  activeThumbColor: Colors.white,
                  onChanged: notifier.setSnapEnabled,
                ),
                if (atPos != null) ...[
                  const SizedBox(height: 8),
                  const CapCutSectionTitle('MORE'),
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
        const CapCutSectionTitle('MUSIC / AUDIO'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Mute original video audio',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          value: editor.muteOriginalAudio,
          activeThumbColor: Colors.white,
          onChanged: notifier.setMuteOriginalAudio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Ducking (music under voice)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          value: editor.duckingEnabled,
          activeThumbColor: Colors.white,
          onChanged: notifier.setDuckingEnabled,
        ),
        Row(
          children: [
            Expanded(
              child: CapCutPillButton(
                label: 'Auto Volume',
                icon: Icons.equalizer,
                filled: false,
                expanded: true,
                height: 36,
                onPressed: notifier.normalizeAudioVolumes,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CapCutPillButton(
                label: 'Add Fades',
                icon: Icons.linear_scale,
                filled: false,
                expanded: true,
                height: 36,
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
        const Text(
          'Voice FX',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
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
        const CapCutSectionTitle('MUSIC LIBRARY'),
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
        const CapCutSectionTitle('SFX LIBRARY'),
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
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.fileName.isEmpty ? 'Audio' : a.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Vol ${(a.volume * 100).round()}% · Fade ${a.fadeInMs}/${a.fadeOutMs}ms'
                    '${a.isVoiceover ? ' · VO' : ''}'
                    '${a.effectId != 'none' ? ' · ${a.effectId}' : ''}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: [
        const CapCutSectionTitle('STYLE'),
        SizedBox(
          height: 96,
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
        const SizedBox(height: 14),
        const CapCutSectionTitle('TEMPLATES'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in FeatureOps.trendingTemplateIds)
              ActionChip(
                label: Text(id, style: const TextStyle(fontSize: 11)),
                onPressed: () => onPreset(id),
                backgroundColor: const Color(0xFF1C1C1C),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const CapCutSectionTitle('BRAND'),
        Wrap(
          spacing: 6,
          children: [
            for (final kit in FeatureOps.brandKits.values)
              ChoiceChip(
                label: Text(kit.name, style: const TextStyle(fontSize: 11)),
                selected: editor.brandKitId == kit.id,
                selectedColor: kit.primary.withValues(alpha: 0.25),
                backgroundColor: const Color(0xFF1C1C1C),
                onSelected: (_) => notifier.applyBrandKit(kit.id),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Text tracking',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          value: editor.textTracking,
          activeThumbColor: Colors.white,
          onChanged: notifier.setTextTracking,
        ),
        Row(
          children: [
            Expanded(
              child: CapCutPillButton(
                label: 'Lyrics style',
                icon: Icons.lyrics_outlined,
                filled: false,
                expanded: true,
                height: 34,
                onPressed: () {
                  final lyrics = FeatureOps.autoLyricsStyle();
                  onPreset(lyrics.presetId);
                  onStyle(lyrics.style);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CapCutPillButton(
                label: 'Smart fill',
                icon: Icons.dashboard_customize_outlined,
                filled: false,
                expanded: true,
                height: 34,
                onPressed: () {
                  final filled = FeatureOps.smartTemplateFill(
                    editor.segments,
                    editor.presetId,
                  );
                  ref
                      .read(editorControllerProvider.notifier)
                      .setSegments(filled);
                  onPreset(
                    FeatureOps.trendingTemplateIds.isEmpty
                        ? 'neon'
                        : FeatureOps.trendingTemplateIds.first,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const CapCutSectionTitle('FONT'),
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
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Size',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const Spacer(),
            Text(
              editor.style.fontSize.toStringAsFixed(0),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Slider(
          min: 24,
          max: 120,
          value: editor.style.fontSize.clamp(24, 120),
          onChanged: (v) => onStyle(editor.style.copyWith(fontSize: v)),
        ),
        Row(
          children: [
            const Text(
              'Horizontal',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const Spacer(),
            Text(
              editor.style.positionX.toStringAsFixed(2),
              style: const TextStyle(
                color: Color(0xFF8E8E8E),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Slider(
          min: 0.1,
          max: 0.9,
          value: editor.style.positionX.clamp(0.1, 0.9),
          onChanged: (v) => onStyle(editor.style.copyWith(positionX: v)),
        ),
        Row(
          children: [
            const Text(
              'Vertical',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const Spacer(),
            Text(
              editor.style.positionY.toStringAsFixed(2),
              style: const TextStyle(
                color: Color(0xFF8E8E8E),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Slider(
          min: 0.08,
          max: 0.92,
          value: editor.style.positionY.clamp(0.08, 0.92),
          onChanged: (v) => onStyle(editor.style.copyWith(positionY: v)),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Drag text on preview · pinch to resize',
            style: TextStyle(
              color: Color(0xFF5C5C5C),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const CapCutSectionTitle('POSITION'),
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
                onSelected: (_) =>
                    onStyle(editor.style.copyWith(positionY: e.$2)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 18),
        const CapCutSectionTitle('MOTION'),
        SizedBox(
          height: 168,
          child: _EffectsGrid(
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

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
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
        const CapCutSectionTitle('MP4 QUALITY'),
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
          const CapCutSectionTitle('FRAME RATE'),
          Wrap(
            spacing: 6,
            children: [
              for (final fps in const [24, 30, 60])
                ChoiceChip(
                  label: Text('$fps fps'),
                  selected: editor.exportFps == fps,
                  onSelected: (_) => notifier.setExportFps(fps),
                  visualDensity: VisualDensity.compact,
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: editor.exportFps == fps
                        ? Colors.black
                        : AppColors.textPrimary,
                  ),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Proxy / performance mode',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            value: editor.proxyMode,
            activeThumbColor: Colors.white,
            onChanged: notifier.setProxyMode,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Hardware acceleration',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            value: editor.hwAccel,
            activeThumbColor: Colors.white,
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
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasKey
                            ? 'AI credits: Gemini key چالاکە'
                            : 'AI credits: API key زیاد بکە',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              color: AppColors.playhead,
              backgroundColor: AppColors.surfaceSoft,
            ),
          ),
        ],
        const SizedBox(height: 14),
        CapCutPillButton(
          label: exporting ? 'Rendering…' : 'Export MP4',
          icon: Icons.movie_creation_outlined,
          busy: exporting,
          expanded: true,
          height: 40,
          onPressed: exporting ? null : onExportMp4,
        ),
        const SizedBox(height: 8),
        CapCutPillButton(
          label: 'Export GIF (3s)',
          icon: Icons.gif_box_outlined,
          filled: false,
          expanded: true,
          height: 38,
          onPressed: exporting ? null : onExportGif,
        ),
        const SizedBox(height: 8),
        CapCutPillButton(
          label: 'Batch: MP4 + SRT + ASS',
          icon: Icons.playlist_add_check,
          filled: false,
          expanded: true,
          height: 38,
          onPressed: exporting ? null : onBatchExport,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CapCutPillButton(
                label: 'Export JSON',
                icon: Icons.upload_file,
                filled: false,
                expanded: true,
                height: 36,
                onPressed: onExportProjectJson,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CapCutPillButton(
                label: 'Import JSON',
                icon: Icons.download,
                filled: false,
                expanded: true,
                height: 36,
                onPressed: onImportProjectJson,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const CapCutSectionTitle('SUBTITLE FILES'),
        Row(
          children: [
            Expanded(
              child: CapCutPillButton(
                label: 'SRT',
                icon: Icons.subtitles_outlined,
                filled: false,
                expanded: true,
                height: 36,
                onPressed: onExportSrt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CapCutPillButton(
                label: 'ASS',
                icon: Icons.style_outlined,
                filled: false,
                expanded: true,
                height: 36,
                onPressed: onExportAss,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// CapCut Text hub: Add text · Auto Captions · Templates · Import.
class _CapCutTextHub extends StatelessWidget {
  const _CapCutTextHub({
    required this.exporting,
    required this.hasCaptions,
    required this.onAddText,
    required this.onAutoCaptions,
    required this.onTemplates,
    this.onImportSrt,
    this.onEditCaptions,
  });

  final bool exporting;
  final bool hasCaptions;
  final VoidCallback onAddText;
  final VoidCallback? onAutoCaptions;
  final VoidCallback onTemplates;
  final VoidCallback? onImportSrt;
  final VoidCallback? onEditCaptions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'Text',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _HubCard(
                icon: Icons.title_rounded,
                title: 'Add text',
                subtitle: 'Title · label',
                onTap: onAddText,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HubCard(
                icon: Icons.closed_caption_rounded,
                title: exporting ? 'Working…' : 'Auto Captions',
                subtitle: 'From speech',
                primary: true,
                onTap: exporting ? null : onAutoCaptions,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _HubCard(
                icon: Icons.auto_awesome_outlined,
                title: 'Templates',
                subtitle: 'Style · motion',
                onTap: onTemplates,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HubCard(
                icon: Icons.upload_file_rounded,
                title: 'Import SRT',
                subtitle: 'Caption file',
                onTap: onImportSrt,
              ),
            ),
          ],
        ),
        if (hasCaptions && onEditCaptions != null) ...[
          const SizedBox(height: 8),
          CapCutPillButton(
            label: 'Edit captions',
            icon: Icons.edit_note_rounded,
            filled: false,
            expanded: true,
            height: 36,
            onPressed: onEditCaptions,
          ),
        ],
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: primary ? const Color(0xFF1A1A1A) : const Color(0xFF161616),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary ? const Color(0xFF3A3A3A) : const Color(0xFF222222),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: primary ? Colors.white : const Color(0xFFB0B0B0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6B6B6B),
                        fontWeight: FontWeight.w500,
                      ),
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
    this.onAutoCaptions,
    this.onImportSrt,
    this.exporting = false,
    this.showToolbar = true,
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
  final VoidCallback? onAutoCaptions;
  final VoidCallback? onImportSrt;
  final bool exporting;
  final bool showToolbar;

  Widget _textTools() {
    SubtitleSegment? active;
    for (final s in segments) {
      if (s.id == activeId) {
        active = s;
        break;
      }
    }
    final hasActive = active != null;

    return ColoredBox(
      color: const Color(0xFF0E0E0E),
      child: Column(
        children: [
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                CapCutToolIcon(
                  icon: Icons.auto_awesome_rounded,
                  label: exporting
                      ? '…'
                      : (segments.isEmpty ? 'Auto' : 'Regen'),
                  enabled: !exporting && onAutoCaptions != null,
                  onTap: exporting ? null : onAutoCaptions,
                ),
                CapCutToolIcon(
                  icon: Icons.add_rounded,
                  label: 'Add',
                  onTap: onAdd,
                ),
                CapCutToolIcon(
                  icon: Icons.upload_file_rounded,
                  label: 'SRT',
                  enabled: onImportSrt != null,
                  onTap: onImportSrt,
                ),
                CapCutToolIcon(
                  icon: Icons.content_cut_rounded,
                  label: 'Split',
                  enabled: hasActive,
                  onTap: hasActive ? () => onSplit(active!.id) : null,
                ),
                CapCutToolIcon(
                  icon: Icons.merge_type_rounded,
                  label: 'Merge',
                  enabled: hasActive,
                  onTap: hasActive ? () => onMergeNext(active!.id) : null,
                ),
                CapCutToolIcon(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  danger: true,
                  enabled: hasActive,
                  onTap: hasActive ? () => onDelete(active!.id) : null,
                ),
                CapCutToolIcon(
                  icon: Icons.backspace_outlined,
                  label: 'Fillers',
                  enabled: onRemoveFillers != null,
                  onTap: onRemoveFillers,
                ),
                CapCutToolIcon(
                  icon: Icons.short_text_rounded,
                  label: 'Sentences',
                  enabled: onSplitSentences != null,
                  onTap: onSplitSentences,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1C1C1C)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(
              children: [
                Text(
                  '${segments.length} captions',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = SubtitleOps.sorted(segments);
    if (sorted.isEmpty) {
      return Column(
        children: [
          if (showToolbar) _textTools(),
          const Expanded(
            child: EmptyHint(
              icon: Icons.subtitles_outlined,
              title: 'No captions yet',
              subtitle: 'Tap Auto or import an SRT file',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (showToolbar) _textTools(),
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
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: widget.selected
            ? const Color(0xFF1A1A1A)
            : const Color(0xFF121212),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.selected
              ? const Color(0xFF3A3A3A)
              : const Color(0xFF1C1C1C),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
            child: Column(
              children: [
                TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'ژێرنووس بنووسە…',
                    filled: true,
                    fillColor: Color(0xFF0A0A0A),
                    border: InputBorder.none,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
