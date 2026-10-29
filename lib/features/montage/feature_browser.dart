import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/video_clip.dart';
import '../subtitle_editor/clip_ops.dart';
import '../subtitle_editor/editor_tool_dock.dart';
import 'feature_catalog.dart';

typedef FeatureTabOpener = void Function(EditorTab tab);

/// Searchable grid of advanced / secondary tools (primary work lives in dock).
class FeatureBrowserPanel extends ConsumerStatefulWidget {
  const FeatureBrowserPanel({
    super.key,
    required this.editor,
    required this.position,
    required this.onOpenTab,
    this.onImportMedia,
    this.onImportSrt,
    this.onExtractAudio,
    this.onBackup,
    this.onAutoCaptions,
    this.onOpenExport,
  });

  final EditorState editor;
  final Duration position;
  final FeatureTabOpener onOpenTab;
  final VoidCallback? onImportMedia;
  final VoidCallback? onImportSrt;
  final VoidCallback? onExtractAudio;
  final VoidCallback? onBackup;
  final VoidCallback? onAutoCaptions;
  final VoidCallback? onOpenExport;

  @override
  ConsumerState<FeatureBrowserPanel> createState() =>
      _FeatureBrowserPanelState();
}

class _FeatureBrowserPanelState extends ConsumerState<FeatureBrowserPanel> {
  final _search = TextEditingController();
  FeatureCategory? _category;
  String _query = '';

  /// Actions that only reopen a primary dock tab — hide unless searching.
  static const _primaryOnlyActions = {
    'open_timeline',
    'open_audio',
    'open_text',
    'open_style',
    'open_animation',
    'open_stickers',
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppFeature> get _items {
    final searching = _query.trim().isNotEmpty;
    final base = _category == null
        ? FeatureCatalog.search(_query)
        : FeatureCatalog.byCategory(_category!)
            .where((f) {
              if (!searching) return true;
              return FeatureCatalog.search(_query).any((x) => x.id == f.id);
            })
            .toList();
    if (searching || _category != null) return base;
    // Default More view: AI, export, planned, and non-primary shortcuts.
    return base.where((f) {
      final a = f.actionId;
      if (a == null) return true;
      if (_primaryOnlyActions.contains(a)) return false;
      return f.category == FeatureCategory.ai ||
          f.category == FeatureCategory.export ||
          f.category == FeatureCategory.templates ||
          f.status != FeatureStatus.ready ||
          a == 'ai_studio' ||
          a == 'generate_captions' ||
          a == 'open_export' ||
          a == 'import_srt' ||
          a == 'import_media' ||
          a == 'backup' ||
          a == 'extract_audio';
    }).toList();
  }

  VideoClip? get _activeClip {
    final id = widget.editor.activeClipId;
    for (final c in widget.editor.videoClips) {
      if (c.id == id) return c;
    }
    return ClipOps.atPosition(widget.editor.videoClips, widget.position);
  }

  Future<void> _run(AppFeature feature) async {
    HapticFeedback.selectionClick();
    final notifier = ref.read(editorControllerProvider.notifier);
    final clip = _activeClip;
    final action = feature.actionId;

    void needClip() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سەرەتا کلیپێک هەڵبژێرە')),
      );
    }

    switch (action) {
      case 'open_timeline':
      case 'split_clip':
        widget.onOpenTab(EditorTab.edit);
        if (action == 'split_clip' && clip != null) {
          notifier.setVideoClips(
            ClipOps.split(widget.editor.videoClips, clip.id, widget.position),
          );
        }
        return;
      case 'duplicate_clip':
        if (clip == null) return needClip();
        notifier.setVideoClips(
          ClipOps.duplicate(widget.editor.videoClips, clip.id),
        );
        return;
      case 'ripple_delete':
        if (clip == null) return needClip();
        if (widget.editor.videoClips.length <= 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ناتوانرێت تاکە کلیپ بسڕدرێتەوە')),
          );
          return;
        }
        notifier.setVideoClips(
          ClipOps.rippleDelete(widget.editor.videoClips, clip.id),
        );
        return;
      case 'reverse_clip':
        if (clip == null) return needClip();
        notifier.setVideoClips(
          ClipOps.toggleReverse(widget.editor.videoClips, clip.id),
        );
        return;
      case 'speed_clip':
      case 'crop_clip':
      case 'rotate_flip':
      case 'opacity':
      case 'clip_volume':
      case 'fade':
      case 'transitions':
      case 'filters':
      case 'adjust':
      case 'effects':
      case 'keyframes':
      case 'merge_clips':
      case 'replace_clip':
      case 'aspect_ratio':
      case 'canvas_color':
      case 'snap':
        widget.onOpenTab(EditorTab.edit);
        return;
      case 'freeze_frame':
        if (clip == null) return needClip();
        notifier.setVideoClips(
          ClipOps.freezeFrame(
            widget.editor.videoClips,
            clip.id,
            widget.position,
          ),
        );
        return;
      case 'import_media':
        widget.onImportMedia?.call();
        return;
      case 'open_audio':
      case 'mute_original':
        if (action == 'mute_original') {
          notifier.setMuteOriginalAudio(!widget.editor.muteOriginalAudio);
        }
        widget.onOpenTab(EditorTab.audio);
        return;
      case 'extract_audio':
        widget.onExtractAudio?.call();
        return;
      case 'open_text':
        widget.onOpenTab(EditorTab.text);
        return;
      case 'generate_captions':
        widget.onOpenTab(EditorTab.text);
        widget.onAutoCaptions?.call();
        return;
      case 'open_style':
      case 'templates':
      case 'open_animation':
        widget.onOpenTab(EditorTab.style);
        return;
      case 'open_stickers':
        widget.onOpenTab(EditorTab.stickers);
        return;
      case 'open_export':
        widget.onOpenExport?.call();
        return;
      case 'import_srt':
        widget.onImportSrt?.call();
        return;
      case 'backup':
        widget.onBackup?.call();
        return;
      case 'undo_redo':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Undo/Redo لە سەرەوەی ئێدیتەر بەردەستە')),
        );
        return;
      case 'ai_soon':
      case 'ai_studio':
        widget.onOpenTab(EditorTab.ai);
        return;
      default:
        if (feature.status == FeatureStatus.planned) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${feature.titleKu} — بەم زووانە')),
          );
        } else {
          widget.onOpenTab(EditorTab.edit);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = FeatureCatalog.all()
        .where((f) => f.status == FeatureStatus.ready)
        .length;
    final partial = FeatureCatalog.all()
        .where((f) => f.status == FeatureStatus.partial)
        .length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'More tools',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${_items.length} · $ready ready',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Search all $ready+$partial tools · AI & export live here',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search all features…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('هەموو', null),
                    for (final c in FeatureCategory.values)
                      _chip(FeatureCatalog.categoryLabel(c), c),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              childAspectRatio: 0.9,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final f = _items[i];
              final color = switch (f.status) {
                FeatureStatus.ready => Colors.white,
                FeatureStatus.partial => const Color(0xFFE8A838),
                FeatureStatus.planned => const Color(0xFF5A5A5A),
              };
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _run(f),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(f.icon, size: 20, color: color),
                    const SizedBox(height: 3),
                    Text(
                      f.titleKu,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                        letterSpacing: -0.1,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, FeatureCategory? cat) {
    final selected = _category == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _category = cat),
        selectedColor: AppColors.brand.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? AppColors.brand : AppColors.textSecondary,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
