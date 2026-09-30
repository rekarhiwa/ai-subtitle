import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/timestamp_utils.dart';
import '../../models/export_quality.dart';
import '../../models/subtitle_animation_config.dart';
import '../../models/subtitle_segment.dart';
import '../../widgets/studio_widgets.dart';
import '../subtitle_styles/subtitle_preset_catalog.dart';
import 'subtitle_ops.dart';

enum EditorTab { text, style, animation, export }

class EditorBottomDock extends StatelessWidget {
  const EditorBottomDock({
    super.key,
    required this.tab,
    required this.onTab,
  });

  final EditorTab tab;
  final ValueChanged<EditorTab> onTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final t in EditorTab.values)
            Expanded(
              child: InkWell(
                onTap: () => onTab(t),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      switch (t) {
                        EditorTab.text => Icons.text_fields_rounded,
                        EditorTab.style => Icons.color_lens_outlined,
                        EditorTab.animation => Icons.auto_awesome,
                        EditorTab.export => Icons.file_upload_outlined,
                      },
                      size: 22,
                      color: tab == t ? AppColors.brand : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      switch (t) {
                        EditorTab.text => 'Text',
                        EditorTab.style => 'Style',
                        EditorTab.animation => 'Effects',
                        EditorTab.export => 'Export',
                      },
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tab == t ? AppColors.brand : AppColors.textSecondary,
                      ),
                    ),
                  ],
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
  });

  final EditorTab tab;
  final EditorState editor;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onExportSrt;
  final VoidCallback onExportAss;
  final VoidCallback onExportMp4;
  final bool asSidePanel;

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
              : const BorderSide(color: AppColors.border),
        ),
      ),
      child: switch (tab) {
        EditorTab.text => CaptionTextPanel(
            segments: editor.segments,
            activeId: active?.id ?? editor.activeSegmentId,
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
          ),
        EditorTab.style => ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const SectionLabel('PRESET'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in SubtitlePresetCatalog.all)
                    ChoiceChip(
                      label: Text(preset.name),
                      selected: editor.presetId == preset.id,
                      onSelected: (_) => notifier.applyPreset(preset.id),
                      selectedColor: AppColors.brand,
                      labelStyle: TextStyle(
                        color: editor.presetId == preset.id
                            ? Colors.black
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
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
                  notifier.updateStyle(editor.style.copyWith(fontFamily: family));
                },
              ),
              const SizedBox(height: 12),
              Text('Size ${editor.style.fontSize.toStringAsFixed(0)}'),
              Slider(
                min: 28,
                max: 90,
                value: editor.style.fontSize.clamp(28, 90),
                onChanged: (v) =>
                    notifier.updateStyle(editor.style.copyWith(fontSize: v)),
              ),
              Text('Position ${editor.style.positionY.toStringAsFixed(2)}'),
              Slider(
                min: 0.45,
                max: 0.9,
                value: editor.style.positionY.clamp(0.45, 0.9),
                onChanged: (v) =>
                    notifier.updateStyle(editor.style.copyWith(positionY: v)),
              ),
            ],
          ),
        EditorTab.animation => ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const SectionLabel('CAPTION ANIMATION'),
              const SizedBox(height: 10),
              for (final type in const [
                SubtitleAnimationType.none,
                SubtitleAnimationType.fade,
                SubtitleAnimationType.pop,
                SubtitleAnimationType.slideUp,
                SubtitleAnimationType.slideLeft,
                SubtitleAnimationType.slideRight,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: editor.animation.type == type
                            ? AppColors.brand
                            : AppColors.border,
                      ),
                    ),
                    tileColor: AppColors.surfaceElevated,
                    title: Text(
                      SubtitleAnimationConfig(
                        type: type,
                      ).label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: editor.animation.type == type
                        ? const Icon(Icons.check_circle, color: AppColors.brand)
                        : null,
                    onTap: () {
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
                          SubtitleAnimationConfig.fade,
                      };
                      notifier.setAnimation(config);
                    },
                  ),
                ),
            ],
          ),
        EditorTab.export => ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const SectionLabel('QUALITY'),
              const SizedBox(height: 8),
              DropdownButtonFormField<ExportQuality>(
                initialValue: editor.exportQuality,
                items: [
                  for (final q in ExportQuality.values)
                    DropdownMenuItem(value: q, child: Text(q.label)),
                ],
                onChanged: (q) {
                  if (q != null) notifier.setExportQuality(q);
                },
              ),
              const SizedBox(height: 16),
              StudioButton(
                label: editor.isExporting ? 'Rendering…' : 'Export MP4',
                icon: Icons.movie_creation_outlined,
                busy: editor.isExporting,
                onPressed: editor.isExporting ? null : onExportMp4,
              ),
              const SizedBox(height: 10),
              StudioButton(
                label: 'Export SRT',
                icon: Icons.subtitles_outlined,
                filled: false,
                onPressed: onExportSrt,
              ),
              const SizedBox(height: 10),
              StudioButton(
                label: 'Export ASS',
                icon: Icons.style_outlined,
                filled: false,
                onPressed: onExportAss,
              ),
            ],
          ),
      },
    );
  }
}

class CaptionTextPanel extends StatelessWidget {
  const CaptionTextPanel({
    super.key,
    required this.segments,
    required this.activeId,
    required this.onTap,
    required this.onChanged,
    required this.onDelete,
    required this.onSplit,
    required this.onMergeNext,
    required this.onAdd,
  });

  final List<SubtitleSegment> segments;
  final String? activeId;
  final ValueChanged<SubtitleSegment> onTap;
  final ValueChanged<SubtitleSegment> onChanged;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSplit;
  final ValueChanged<String> onMergeNext;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final sorted = SubtitleOps.sorted(segments);
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
              return _SegmentTile(
                segment: s,
                selected: s.id == activeId,
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

class _SegmentTile extends StatefulWidget {
  const _SegmentTile({
    required this.segment,
    required this.selected,
    required this.onTap,
    required this.onChanged,
    required this.onDelete,
    required this.onSplit,
    required this.onMergeNext,
  });

  final SubtitleSegment segment;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<SubtitleSegment> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final VoidCallback onMergeNext;

  @override
  State<_SegmentTile> createState() => _SegmentTileState();
}

class _SegmentTileState extends State<_SegmentTile> {
  late final TextEditingController _text;
  late final TextEditingController _start;
  late final TextEditingController _end;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.segment.text);
    _start = TextEditingController(text: TimestampUtils.toUi(widget.segment.start));
    _end = TextEditingController(text: TimestampUtils.toUi(widget.segment.end));
  }

  @override
  void didUpdateWidget(covariant _SegmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.id != widget.segment.id ||
        oldWidget.segment.text != widget.segment.text) {
      _text.text = widget.segment.text;
    }
    if (oldWidget.segment.start != widget.segment.start) {
      _start.text = TimestampUtils.toUi(widget.segment.start);
    }
    if (oldWidget.segment.end != widget.segment.end) {
      _end.text = TimestampUtils.toUi(widget.segment.end);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _commit() {
    final start = TimestampUtils.tryParse(_start.text) ?? widget.segment.start;
    final end = TimestampUtils.tryParse(_end.text) ?? widget.segment.end;
    widget.onChanged(
      widget.segment.copyWith(
        text: _text.text.trim().isEmpty ? widget.segment.text : _text.text.trim(),
        start: start,
        end: end > start ? end : start + const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.selected
          ? AppColors.brand.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Column(
                  children: [
                    TextField(
                      controller: _start,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'In',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onEditingComplete: _commit,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _end,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Out',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onEditingComplete: _commit,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Caption',
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Split',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onSplit,
                    icon: const Icon(Icons.call_split, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Merge',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onMergeNext,
                    icon: const Icon(Icons.merge_type, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
