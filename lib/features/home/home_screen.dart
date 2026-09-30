import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/studio_widgets.dart';
import '../settings/settings_screen.dart';
import '../subtitle_editor/subtitle_editor_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final apiKeyAsync = ref.watch(apiKeyProvider);
    final hasKey = (apiKeyAsync.asData?.value ?? '').isNotEmpty;

    ref.listen(homeControllerProvider, (prev, next) async {
      if (prev?.phase != ProcessingPhase.done &&
          next.phase == ProcessingPhase.done &&
          next.video != null &&
          next.segments.isNotEmpty) {
        await ref.read(editorControllerProvider.notifier).open(
              video: next.video!,
              segments: next.segments,
            );
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SubtitleEditorScreen(),
            ),
          );
          // Reset processing chrome when returning from editor.
          ref.read(homeControllerProvider.notifier).resetPhase();
        }
      }
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.movie_filter, color: Colors.black, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Subtitle',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Edit like CapCut · Kurdish captions',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SoftCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ژێرنووسی زیر بۆ ڤیدیۆکەت',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Import → Auto caption → Edit like CapCut → Export MP4',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: const [
                                _Pill(icon: Icons.phonelink_lock, label: 'Local FFmpeg'),
                                _Pill(icon: Icons.auto_awesome, label: 'Gemini AI'),
                                _Pill(icon: Icons.timeline, label: 'Timeline edit'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!hasKey)
                        SoftCard(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.key, color: AppColors.warning),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Add Gemini API key in Settings to generate captions',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      if (!hasKey) const SizedBox(height: 14),
                      _ImportZone(
                        busy: state.isBusy,
                        onSelect: () => _pickVideo(context, controller),
                      ),
                      if (state.video != null) ...[
                        const SizedBox(height: 14),
                        _ProjectCard(state: state, onChange: () => _pickVideo(context, controller)),
                        const SizedBox(height: 14),
                        SoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionLabel('CAPTION LANGUAGE'),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.translate, color: AppColors.brand, size: 18),
                                    SizedBox(width: 10),
                                    Text(
                                      'Kurdish Sorani · کوردی سۆرانی',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Spacer(),
                                    Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: StudioButton(
                                      label: state.isBusy ? 'Working…' : 'Auto Captions',
                                      icon: Icons.auto_awesome,
                                      busy: state.isBusy,
                                      onPressed: state.isBusy
                                          ? null
                                          : () => controller.generateSubtitles(),
                                    ),
                                  ),
                                  if (state.isBusy) ...[
                                    const SizedBox(width: 10),
                                    StudioButton(
                                      label: 'Cancel',
                                      filled: false,
                                      expanded: false,
                                      onPressed: () => controller.cancel(),
                                    ),
                                  ],
                                ],
                              ),
                              if (state.segments.isNotEmpty &&
                                  state.phase == ProcessingPhase.idle) ...[
                                const SizedBox(height: 10),
                                StudioButton(
                                  label: 'Open Editor',
                                  icon: Icons.movie_filter,
                                  filled: false,
                                  onPressed: () async {
                                    await ref.read(editorControllerProvider.notifier).open(
                                          video: state.video!,
                                          segments: state.segments,
                                        );
                                    if (context.mounted) {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const SubtitleEditorScreen(),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (state.isBusy ||
                          state.phase == ProcessingPhase.error) ...[
                        const SizedBox(height: 14),
                        _ProcessingPanel(state: state),
                      ],
                      const SizedBox(height: 20),
                      const SectionLabel('WORKFLOW'),
                      const SizedBox(height: 10),
                      const _WorkflowSteps(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickVideo(BuildContext context, HomeController controller) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    try {
      await controller.selectVideo(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ImportZone extends StatelessWidget {
  const _ImportZone({required this.onSelect, required this.busy});
  final VoidCallback onSelect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onSelect,
        borderRadius: BorderRadius.circular(18),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: busy ? AppColors.border : AppColors.brand.withValues(alpha: 0.55),
            radius: 18,
          ),
          child: Container(
            width: double.infinity,
            height: 168,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.add_to_photos_outlined,
                    color: busy ? AppColors.textMuted : AppColors.brand,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  busy ? 'Please wait…' : 'Import video',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'MP4 · MOV · MKV · WEBM',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.state, required this.onChange});
  final HomeState state;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final video = state.video!;
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 92,
              height: 120,
              child: video.thumbnailPath != null &&
                      File(video.thumbnailPath!).existsSync()
                  ? Image.file(File(video.thumbnailPath!), fit: BoxFit.cover)
                  : Container(
                      color: AppColors.surfaceElevated,
                      child: const Icon(Icons.movie, size: 32),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                _meta(Icons.schedule, video.durationLabel),
                const SizedBox(height: 6),
                _meta(Icons.aspect_ratio, video.resolutionLabel),
                const SizedBox(height: 6),
                _meta(Icons.sd_storage_outlined, video.fileSizeLabel),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: state.isBusy ? null : onChange,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Change'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel({required this.state});
  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (ProcessingPhase.extractingAudio, 'Extract audio'),
      (ProcessingPhase.uploadingAudio, 'Upload audio'),
      (ProcessingPhase.generatingSubtitles, 'AI captions'),
      (ProcessingPhase.preparingTimeline, 'Build timeline'),
    ];

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.phase == ProcessingPhase.error
                      ? (state.errorMessage ?? 'Something went wrong')
                      : (state.statusMessage.isEmpty
                          ? 'Processing…'
                          : state.statusMessage),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: state.phase == ProcessingPhase.error ? 13 : 15,
                    color: state.phase == ProcessingPhase.error
                        ? AppColors.danger
                        : AppColors.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
              if (state.phase != ProcessingPhase.error)
                Text(
                  '${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: state.phase == ProcessingPhase.error
                  ? 1
                  : state.progress.clamp(0.0, 1.0),
              minHeight: 7,
              color: state.phase == ProcessingPhase.error
                  ? AppColors.danger
                  : AppColors.brand,
              backgroundColor: AppColors.surfaceElevated,
            ),
          ),
          const SizedBox(height: 16),
          ...steps.map((step) {
            final active = state.phase == step.$1;
            final done = state.phase == ProcessingPhase.done ||
                (state.phase != ProcessingPhase.error &&
                    state.phase.index > step.$1.index);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.success
                          : active
                              ? AppColors.brand
                              : AppColors.surfaceElevated,
                      border: Border.all(
                        color: done || active ? Colors.transparent : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.circle,
                      size: done ? 14 : 8,
                      color: done || active ? Colors.black : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    step.$2,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: active || done
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WorkflowSteps extends StatelessWidget {
  const _WorkflowSteps();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('1', 'Import', 'Pick a local video'),
      ('2', 'Auto', 'Gemini makes Kurdish captions'),
      ('3', 'Edit', 'Timeline, style, animation'),
      ('4', 'Export', 'SRT / ASS / burned MP4'),
    ];
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.surfaceElevated,
                child: Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brand,
                  ),
                ),
              ),
              title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(item.$3, style: const TextStyle(color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}
