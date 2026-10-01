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

/// CapCut-style searchable grid of all 136 features.
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
  });

  final EditorState editor;
  final Duration position;
  final FeatureTabOpener onOpenTab;
  final VoidCallback? onImportMedia;
  final VoidCallback? onImportSrt;
  final VoidCallback? onExtractAudio;
  final VoidCallback? onBackup;

  @override
  ConsumerState<FeatureBrowserPanel> createState() =>
      _FeatureBrowserPanelState();
}

class _FeatureBrowserPanelState extends ConsumerState<FeatureBrowserPanel> {
  final _search = TextEditingController();
  FeatureCategory? _category;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppFeature> get _items {
    final base = _category == null
        ? FeatureCatalog.search(_query)
        : FeatureCatalog.byCategory(_category!)
            .where((f) {
              if (_query.trim().isEmpty) return true;
              return FeatureCatalog.search(_query).any((x) => x.id == f.id);
            })
            .toList();
    return base;
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
      case 'open_style':
      case 'templates':
        widget.onOpenTab(EditorTab.style);
        return;
      case 'open_animation':
        widget.onOpenTab(EditorTab.animation);
        return;
      case 'open_stickers':
        widget.onOpenTab(EditorTab.stickers);
        return;
      case 'open_export':
        widget.onOpenTab(EditorTab.export);
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
                    '١٣٦ تایبەتمەندی',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const Spacer(),
                  Text(
                    '$ready ئامادە · $partial بەش',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'گەڕان… Split, captions, AI…',
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
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final f = _items[i];
              final color = switch (f.status) {
                FeatureStatus.ready => AppColors.brand,
                FeatureStatus.partial => const Color(0xFFE8A838),
                FeatureStatus.planned => AppColors.textSecondary,
              };
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _run(f),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                    ),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(f.icon, size: 22, color: color),
                      const SizedBox(height: 4),
                      Text(
                        '${f.number}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      Text(
                        f.titleKu,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
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
